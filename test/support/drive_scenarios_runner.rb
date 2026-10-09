# frozen_string_literal: true

# The true-drive scenarios runner. bin/drive_scenarios runs
# DriveScenarios.main and documents its options.

lib = File.expand_path("../../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "fileutils"
require "tmpdir"
require_relative "cli"
require_relative "drive_scenarios"

module DriveScenarios
  HARNESS = File.expand_path("../../spinel/drive_scenarios.rb", __dir__)

  module_function

  def selected(filters)
    return CHECKS.keys if filters.empty?

    CHECKS.keys.select { |name| filters.any? { |filter| name.include?(filter) } }
  end

  def unmatched(filters)
    filters.reject { |filter| CHECKS.keys.any? { |name| name.include?(filter) } }
  end

  def command(engine, dir, name)
    return [engine, dir, name] if engine

    [RbConfig.ruby, "--yjit", "-I", File.expand_path("../../lib", __dir__), HARNESS, dir, name]
  end

  # Runs the scenarios, up to shards at once, and returns their rows keyed
  # by scenario. TERM or INT is passed on to every running scenario, and
  # the run stops once they have.
  def run(names, shards, engine)
    Dir.mktmpdir("drive-scenarios") { |root| Pool.new(root, engine).run(names, shards) }
  end

  # The scenario processes running side by side.
  class Pool
    def initialize(root, engine)
      @root = root
      @engine = engine
      @running = {}
      @rows = {}
      @interrupted = nil
    end

    def run(names, shards)
      queue = names.dup
      forwarding_signals do
        until (queue.empty? || @interrupted) && @running.empty?
          start(queue.shift) while @running.length < shards && !queue.empty? && !@interrupted
          reap
        end
      end
      raise Interrupt, "drive_scenarios interrupted by SIG#{@interrupted}. No results written." if @interrupted

      @rows
    end

    private

    def forwarding_signals
      previous = %w[TERM INT].to_h { |signal| [signal, trap(signal) { interrupt(signal) }] }
      yield
    ensure
      previous&.each { |signal, handler| trap(signal, handler) }
    end

    def start(name)
      dir = File.join(@root, name)
      FileUtils.mkdir_p(dir)
      @running[Process.spawn(*DriveScenarios.command(@engine, dir, name), out: out(name))] = name
    end

    def reap
      pid, status = Process.wait2
      name = @running.delete(pid)
      @rows[name] = DriveScenarios.finish(name, File.read(out(name)), status) if name
    end

    def out(name) = File.join(@root, "#{name}.out")

    def interrupt(signal)
      @interrupted ||= signal
      @running.each_key do |pid|
        Process.kill(signal, pid)
      rescue Errno::ESRCH
        nil
      end
    end
  end

  # The scenario's rows, with a FAIL row for each check its process didn't
  # report.
  def finish(name, output, status)
    reported = output.lines.to_h { |line| [line.split("\t", 2).first, line] }
    lines = CHECKS.fetch(name).map do |check|
      id = "#{name}/#{check}"
      reported.fetch(id) { "#{id}\tFAIL\tcrashed: #{status}\n" }
    end
    lines.each { |line| print line.tr("\t", " ") }
    $stdout.flush
    lines
  end

  def main(argv)
    list_only = argv.delete("--list")
    results_path = CLI.take_option(argv, "--results")
    shards = CLI.shard_count(CLI.take_option(argv, "--shards"))
    engine = CLI.take_option(argv, "--engine")
    unmatched = unmatched(argv)
    unless unmatched.empty?
      warn "No scenario matches #{unmatched.join(', ')}."
      return 2
    end

    names = selected(argv)
    if list_only
      puts names
      return 0
    end

    rows = run(names, shards, engine)
    summarize(names.flat_map { |name| rows.fetch(name) }, results_path)
  end

  # Prints the pass count and writes the results, returning the exit status.
  def summarize(lines, results_path)
    failed = lines.count { |line| line.split("\t")[1].chomp != "PASS" }
    puts "#{lines.length - failed}/#{lines.length} passed"
    if results_path
      FileUtils.mkdir_p(File.dirname(results_path))
      File.write(results_path, lines.join)
    end
    failed.zero? ? 0 : 1
  end
end
