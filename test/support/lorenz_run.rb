# frozen_string_literal: true

require "digest"

# The reporting half of the Wolfgang Lorenz runner, on CRuby only: it turns
# a run of the chain (Lorenz::Chain in test/support/lorenz_chain.rb) into one
# baseline row per test, whether bin/lorenz drove the chain in process or
# a Spinel build of spinel/lorenz.rb drove it and printed what it recorded.
module Lorenz
  DEFAULT_IMAGE = File.expand_path(
    "../../vendor/VICE-testprogs/general/Lorenz-2.15/Lorenz.d81", __dir__
  )

  # The suite's plus4 build, disks 1-3, which bin/lorenz --plus4 runs.
  PLUS4_IMAGE = File.expand_path(
    "../../vendor/VICE-testprogs/general/Lorenz-2.15/LorenzPlus4.d81", __dir__
  )

  # A test that neither ends in the suite's "- ok" nor prints anything
  # beyond its own name has failed; the dumps it prints instead say so.
  # Several of those dumps name neither word and then fall through to the
  # suite's own "- ok" exit path, so the keypress they halt for is the only
  # reliable signal — a segment an injection landed in has failed.
  OK_SUFFIX = "- ok"
  FAILURE_MARKER = /fail|error/i

  # Detail long enough to bury the row (the CIA dump tests print tables)
  # is cut down to a digest, which still changes whenever the dump does.
  DETAIL_LIMIT = 160

  # One test's slice of the transcript, reduced to a verdict and a detail
  # column. The loader announces the next test's name before handing over,
  # so that announcement is trimmed off the end of the slice it precedes.
  class Segment
    attr_reader :name

    def initialize(name, text, halted:)
      @name = name
      @text = text
      @halted = halted
    end

    def verdict
      passed? ? "PASS" : "FAIL"
    end

    def detail
      @detail ||= abbreviate([("halted for a keypress" if @halted), printed]
                               .compact.join(" | "))
    end

    def to_record
      [name, verdict, (detail unless detail.empty?)].compact.join("\t")
    end

    private

    def passed?
      !@halted && @text.rstrip.end_with?(OK_SUFFIX) && !body.match?(FAILURE_MARKER)
    end

    def printed
      body.gsub(/\s*\n\s*/, " | ").squeeze(" ").strip
    end

    # Both the loader and the test itself echo the name, sometimes with a
    # " (old cia)" variant marker appended to the second one.
    def body
      @body ||= begin
        text = @text.strip
        text = text.delete_prefix(name).strip while text.start_with?(name)
        text.delete_suffix(OK_SUFFIX).strip
      end
    end

    def abbreviate(detail)
      return detail if detail.length <= DETAIL_LIMIT

      "#{detail[0, DETAIL_LIMIT - 20].rstrip}… sha=#{Digest::SHA256.hexdigest(detail)[0, 8]}"
    end
  end

  # How a run of the chain went: the transcript, the programs it loaded and
  # the transcript offsets they arrived at, the offsets keys were injected
  # at, and how it ended.
  #
  # The suite chains itself by LOADing one test after another, so the names
  # it asks the mounted image for split the capture into one segment per
  # test.
  class Run
    Load = Struct.new(:name, :offset)

    attr_reader :transcript, :result

    # Reads what spinel/lorenz.rb prints: "load OFFSET NAME", "key OFFSET"
    # and "result RESULT CYCLES" lines, then "transcript LENGTH" and the
    # transcript itself.
    def self.parse(output)
      header, length, transcript = output.split(/^transcript (\d+)\n/, 2)
      raise ArgumentError, "The transcript is missing or cut short" unless transcript&.length == length.to_i

      lines = header.lines(chomp: true).map { |line| line.split(" ", 3) }.group_by(&:first)
      loads = lines.fetch("load", []).map { |_, offset, name| [name, offset.to_i] }
      keys = lines.fetch("key", []).map { |_, offset| offset.to_i }
      result = lines.fetch("result", []).dig(0, 1)
      new(transcript, loads, keys, result)
    end

    # loads holds a [name, offset] pair for each program loaded. skipped
    # names the tests a run stuck on and resumed past (Lorenz.segments).
    def initialize(transcript, loads, key_offsets, result, skipped = [])
      @transcript = transcript
      @loads = loads.map { |name, offset| Load.new(name, offset) }
      @key_offsets = key_offsets
      @result = result
      @skipped = skipped
    end

    # The names of the programs loaded, in order.
    def names = @loads.map(&:name)

    # The runs one after another as one: their transcripts joined, each
    # one's offsets moved past the runs before it, and the last one's
    # result.
    def self.join(runs)
      transcript = +""
      loads = []
      keys = []
      runs.each do |run|
        base = transcript.length
        loads.concat(run.loads_from(base))
        keys.concat(run.keys_from(base))
        transcript << run.transcript
      end
      skipped = runs[0...-1].map { |run| run.names.last }
      new(transcript, loads, keys, runs.last.result, skipped)
    end

    def loads_from(base) = @loads.map { |load| [load.name, load.offset + base] }

    def keys_from(base) = @key_offsets.map { |offset| offset + base }

    # A test's segment is whole once the chain loads the next one, or when
    # the suite ends on its own. Stopping or timing out cuts the last one.
    def segments
      whole = %w[stopped timeout].include?(@result) ? @loads.length - 1 : @loads.length
      @loads.take(whole).each_with_index.map do |load, index|
        following = @loads[index + 1]
        span = load.offset...(following&.offset || transcript.length)
        text = transcript[span]
        text = text.delete_suffix(following.name) if following
        Segment.new(load.name, text, halted: @key_offsets.any? { span.cover?(it) })
      end
    end

    # The chain can break mid-suite, which would otherwise only show up as
    # rows going missing — a keyed diff reports those without failing.
    def outcome_record
      last = @loads.last&.name
      detail = last ? "#{@result} after #{last}" : @result
      detail += ", resumed past #{@skipped.join(', ')}" if @skipped.any?
      ["(suite)", @result == "completed" ? "PASS" : "FAIL", detail].join("\t")
    end

    def records
      segments.map(&:to_record) << outcome_record
    end
  end

  # Where a chain that sticks goes on: the program after the one it stuck
  # on, in the order the disks hold them, the image's programs and then
  # the next disk's.
  class Resumption
    STUCK = %w[hung ready-prompt stuck].freeze

    # +order+ is the programs' names in the order the disks hold them.
    def initialize(order)
      @order = order
    end

    # The order of the programs on +image+ and, beside it, +next_disk+.
    def self.for(image, next_disk)
      paths = [image, File.join(File.dirname(image), next_disk)].select { |path| File.exist?(path) }
      new(paths.flat_map { |path| names(path) })
    end

    # The programs on the disk image at +path+, in directory order.
    def self.names(path)
      lib = File.expand_path("../../lib", __dir__)
      $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
      require "badline/core"
      Lorenz.open_image(path).send(:entries).map { |entry| entry[:name] }.uniq
    end

    # The program to resume at after +run+, or nil when it didn't stick
    # or stuck on the last program.
    def after(run)
      return unless STUCK.include?(run.result)

      index = @order.index(run.names.last)
      index && @order[index + 1]
    end
  end

  # Runs the chain from resume (nil for the top) with the block, which
  # takes a resume name and returns a Run, and goes on past each program
  # it sticks on, so a test that hangs on this machine doesn't end the
  # chain. Returns the runs joined.
  def self.segments(resumption, resume)
    runs = []
    loop do
      run = yield resume
      runs << run
      resume = resumption.after(run)
      return Run.join(runs) unless resume
    end
  end
end
