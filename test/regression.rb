# frozen_string_literal: true

# Suite results are compared by test id rather than line by line, so a test
# inserted upstream does not shift every row after it. Only ids present on
# both sides can fail the run: a test the vendored suite has gained or lost
# is reported but tolerated, since badline got neither better nor worse for
# it. Re-recording the baseline is what pins a new row's verdict.
module Regression
  Row = Struct.new(:key, :verdict, :detail) do
    # The occurrence suffix is a read-side key, not part of the recorded id.
    def id
      key.sub(/#\d+\z/, "")
    end

    def to_s
      [verdict, detail].compact.join(" ")
    end

    def to_record
      "#{[id, verdict, detail].compact.join("\t")}\n"
    end
  end

  # A few testlist entries are listed twice, so an id that repeats is keyed
  # by its occurrence.
  def self.read(path)
    seen = Hash.new(0)
    File.readlines(path, chomp: true).reject(&:empty?).to_h do |line|
      id, verdict, detail = line.split("\t", 3)
      seen[id] += 1
      key = seen[id] > 1 ? "#{id}##{seen[id]}" : id
      [key, Row.new(key, verdict, detail)]
    end
  end

  def self.write(path, rows)
    File.write(path, rows.map(&:to_record).join)
  end

  # Merges a filtered run into a recorded baseline. A row the run produced
  # replaces its baseline row in place; a row the run did not touch is kept
  # verbatim; a row the baseline does not have yet is inserted next to the
  # run's neighbouring row. Nothing is ever dropped, so a row the vendored
  # suite lost survives a partial record and is reported as gone by the
  # next comparison.
  #
  # Baseline order decides the recorded occurrence numbering (`id#2`), so
  # every inserted row is placed adjacent to the row it followed in the
  # run, never appended past an occurrence of the same id.
  class Splice
    def initialize(baseline, fresh)
      @baseline = baseline
      @fresh = fresh
      place
    end

    def rows
      @rows ||= @baseline.keys.flat_map do |key|
        [*take(@before[key]), @fresh.fetch(key, @baseline[key]), *take(@after[key])]
      end + take(@tail)
    end

    def replaced
      @replaced ||= @fresh.keys & @baseline.keys
    end

    def inserted
      @inserted ||= @fresh.keys - @baseline.keys
    end

    def summary
      "#{replaced.length} row(s) re-recorded, #{inserted.length} inserted, " \
        "#{@baseline.length - replaced.length} left untouched"
    end

    private

    # Walks the run in order, hanging each unrecorded row off the closest
    # recorded row on either side of it.
    def place
      @before = Hash.new { |hash, key| hash[key] = [] }
      @after = Hash.new { |hash, key| hash[key] = [] }
      @tail = []
      pending = []
      anchor = nil
      @fresh.each_key do |key|
        next pending << key unless @baseline.key?(key)

        @before[key].concat(pending.slice!(0..))
        anchor = key
      end
      (anchor ? @after[anchor] : @tail).concat(pending)
    end

    def take(keys)
      keys.map { |key| @fresh[key] }
    end
  end

  # A stretch of a suite that chains itself, one LOAD after the next, so a
  # partial run is a range of the chain rather than a set of ids. Resuming
  # at a test by typing its LOAD leaves the READY prompt and the typed name
  # in that test's segment, so the run resumes one test earlier and throws
  # that segment away. The outcome row records how the whole chain ended,
  # which a partial run cannot say, so it is never part of the range.
  class ChainRange
    OUTCOME = "(suite)"

    attr_reader :first, :last

    def initialize(baseline, first, last = nil)
      @keys = baseline.keys - [OUTCOME]
      @first = first
      @last = last || first
      [@first, @last].each do |name|
        raise ArgumentError, "#{name} is not a row of the baseline. Check the test name." unless @keys.include?(name)
      end
      raise ArgumentError, "#{@last} comes before #{@first} in the chain." if index(@last) < index(@first)
    end

    # The test to resume at, or nil to autostart the chain from its first
    # row, which is also what resuming at that row would load.
    def resume_at
      @keys[index(@first) - 1] if index(@first) > 1
    end

    # The rows from first to last in the order the run reached them, or up
    # to wherever it ended if it never reached last.
    def select(fresh)
      keys = fresh.keys - [OUTCOME]
      from = keys.index(@first)
      raise ArgumentError, "The run never reached #{@first}." unless from

      to = keys.index(@last) || (keys.length - 1)
      fresh.slice(*keys[from..to])
    end

    def reached?(rows)
      rows.key?(@last)
    end

    private

    def index(name)
      @keys.index(name)
    end
  end

  class Comparison
    LIST_LIMIT = 50

    def initialize(suite, baseline, current)
      @suite = suite
      @baseline = baseline
      @current = current
    end

    def changed
      @changed ||= (@baseline.keys & @current.keys).filter_map do |key|
        [@baseline[key], @current[key]] unless @baseline[key] == @current[key]
      end
    end

    def added
      @added ||= @current.values_at(*(@current.keys - @baseline.keys))
    end

    def removed
      @removed ||= @baseline.values_at(*(@baseline.keys - @current.keys))
    end

    def changed?
      changed.any?
    end

    def summary
      passing, failing = added.partition { |row| row.verdict == "PASS" }
      "#{@suite}: #{changed.length} changed, #{added.length} new " \
        "(#{passing.length} pass, #{failing.length} fail), #{removed.length} gone"
    end

    def report(io)
      io.puts(summary)
      changed.each { |before, after| io.puts("  changed #{before.key}: #{before} -> #{after}") }
      added.each { |row| io.puts("  new     #{row.key}: #{row}") }
      removed.each { |row| io.puts("  gone    #{row.key}: #{row}") }
    end

    # regression.yml runs nightly or on demand, where nobody reads the log.
    def publish
      path = ENV.fetch("GITHUB_STEP_SUMMARY", nil)
      File.write(path, markdown, mode: "a") if path
    end

    def markdown
      sections = [
        section("Changed — fails the run",
                changed.map { |before, after| "`#{before.key}`: `#{before}` → `#{after}`" }),
        section("New upstream tests", added.map { |row| "`#{row.key}`: `#{row}`" }),
        section("Removed upstream tests", removed.map { |row| "`#{row.key}`: `#{row}`" })
      ].compact
      "#{["### #{summary}", *sections].join("\n\n")}\n"
    end

    private

    def section(title, lines)
      return if lines.empty?

      shown = lines.take(LIST_LIMIT).map { |line| "- #{line}" }
      shown << "- …and #{lines.length - LIST_LIMIT} more" if lines.length > LIST_LIMIT
      ["**#{title}**", *shown].join("\n")
    end
  end
end
