# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require_relative "../test/lorenz_run"

# Builds the Spinel harnesses and checks each compiled binary against the
# same harness on CRuby. Backs the spinel:build, spinel:check and
# spinel:lorenz tasks.
module SpinelCheck
  OUT = "tmp/spinel"
  HARNESSES = %w[boot cpu_tests].freeze
  CASES = "#{OUT}/cases.txt".freeze

  module_function

  def build(spinel, cc: nil, harnesses: HARNESSES)
    FileUtils.mkdir_p(OUT)
    harnesses.each do |name|
      args = [spinel, "-I", "lib", "--no-line-map", "--rbs", "spinel/sig", "spinel/#{name}.rb", "-o", binary(name)]
      args << "--cc=#{cc}" if cc
      puts args.join(" ")
      system(*args) || raise("Spinel failed to build spinel/#{name}.rb")
    end
  end

  def check_boot(*args)
    compare("boot", args) { |out| out.reject { |line| line.start_with?("timed ") } }
  end

  def check_cpu_tests
    convert_cases unless File.exist?(CASES)
    compare("cpu_tests", [CASES]) { |out| out.grep(/^(FAIL|passed) /) }
  end

  def compare(name, args)
    spinel = yield run(binary(name), *args)
    cruby = yield run(RbConfig.ruby, "--yjit", "-Ilib", "spinel/#{name}.rb", *args)
    puts spinel.last(3)
    raise "spinel/#{name}.rb differs between Spinel and CRuby:\n#{diff(spinel, cruby)}" unless spinel == cruby

    puts "#{name}: Spinel matches CRuby"
  end

  # Runs the compiled Lorenz harness once for each named list of arguments,
  # all side by side, and returns the path of each run's rows in the
  # baseline format. TERM or INT is passed on to every run, and the task
  # fails once they have all stopped.
  def run_lorenz(runs, image: Lorenz::DEFAULT_IMAGE)
    pids = runs.to_h do |name, args|
      command = [binary("lorenz"), image, *args]
      puts command.join(" ")
      [Process.spawn(*command, out: "#{OUT}/#{name}.out"), name]
    end
    failed = wait_all(pids)
    raise "#{failed.join(', ')} failed." if failed.any?

    runs.keys.to_h { |name| [name, lorenz_results(name)] }
  end

  # Waits for every run, returning the names of those that failed.
  def wait_all(pids)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    previous = %w[TERM INT].to_h do |signal|
      [signal, trap(signal) { pids.each_key { |pid| forward(signal, pid) } }]
    end
    failed = []
    until pids.empty?
      pid, status = Process.wait2
      next unless (name = pids.delete(pid))

      puts "#{name}: #{status} after #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round} s"
      failed << name unless status.success?
    end
    failed
  ensure
    previous&.each { |signal, handler| trap(signal, handler) }
  end

  def forward(signal, pid)
    Process.kill(signal, pid)
  rescue Errno::ESRCH
    nil
  end

  def lorenz_results(name)
    results = "#{OUT}/#{name}.txt"
    run = Lorenz::Run.parse(File.read("#{OUT}/#{name}.out"))
    File.write(results, "#{run.records.join("\n")}\n")
    results
  end

  def convert_cases
    system(RbConfig.ruby, "-Ilib", "spinel/convert.rb", "100", CASES) || raise("Converting SingleStepTests failed")
  end

  def run(*command)
    out, status = Open3.capture2(*command)
    raise "#{command.join(' ')} exited with #{status.exitstatus}" unless status.success?

    out.lines(chomp: true)
  end

  def diff(spinel, cruby)
    lines = (spinel - cruby).map { |line| "spinel: #{line}" }
    lines += (cruby - spinel).map { |line| "cruby:  #{line}" }
    lines.join("\n")
  end

  def binary(name)
    "#{OUT}/#{name}"
  end
end
