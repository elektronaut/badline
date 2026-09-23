# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"

# Builds the Spinel harnesses and checks each compiled binary against the
# same harness on CRuby. Backs the spinel:build and spinel:check tasks.
module SpinelCheck
  OUT = "tmp/spinel"
  HARNESSES = %w[boot cpu_tests].freeze
  CASES = "#{OUT}/cases.txt".freeze

  module_function

  def build(spinel, cc: nil)
    FileUtils.mkdir_p(OUT)
    HARNESSES.each do |name|
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
