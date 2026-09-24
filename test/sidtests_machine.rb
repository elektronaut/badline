# frozen_string_literal: true

# The machine-driving half of the SID testprog runner: running one test on a
# machine and turning the $D7FF exit code it reports into a baseline row. It
# stays inside the Ruby subset Spinel compiles, so bin/sidtests on CRuby and
# spinel/sidtests.rb on a Spinel build score a test the same way.
module SIDTests
  BOOT_ALLOWANCE = 3_000_000
  BATCH = 10_000

  SID_MODELS = { "6581" => :mos6581, "8580" => :mos8580 }.freeze

  # Attaches the .prg at path and runs until it reports an exit code or
  # runs out of its budget of cycles after boot. Returns PASS, the exit
  # code it failed with, or timeout. Nothing reads the display, so the VIC
  # leaves its colours unpainted.
  def self.exit_code(computer, path, timeout)
    computer.vic.render = false
    Badline::Media.attach(computer, path)
    register = ExitCode.new
    computer.install_debug_register { |value| register.code = value }
    BATCH.times { computer.cycle! } until register.code || computer.cycles > timeout + BOOT_ALLOWANCE
    verdict(register.code)
  end

  def self.verdict(code)
    return "timeout" if code.nil?
    return "PASS" if code.zero?

    "exit=$#{code.to_s(16).rjust(2, '0')}"
  end

  def self.record(name, result)
    result == "PASS" ? "#{name}\tPASS\n" : "#{name}\tFAIL\t#{result}\n"
  end

  # The last value the test wrote to the debug register.
  class ExitCode
    attr_accessor :code

    def initialize
      @code = nil
    end
  end
end
