# frozen_string_literal: true

# Which rows bin/testbench --plus4 and --c16 run, from plus4-testlist.in,
# and the machine each asks for. The machine-driving half is in
# test/support/testbench_plus4_machine.rb, which the Spinel build shares.
module Testbench
  PLUS4_TESTLIST = File.expand_path("../../vendor/VICE-testprogs/testbench/plus4-testlist.in", __dir__)

  # A TestCase's machine, when the row is the 264 series', and its run.
  module Plus4Row
    def plus4? = %i[plus4 c16].include?(family)

    # The model the row runs on: the family's, its NTSC board for ted-ntsc.
    def plus4_model
      model = family.to_s
      options.include?("ted-ntsc") ? "#{model}ntsc" : model
    end

    # The machine the row's tests fork from: booted, or at power-on for a
    # cartridge.
    def plus4_machine = Testbench.plus4_machine(plus4_model, cartridge.nil?)

    # Runs the row on +machine+, returning the exit code and the text
    # screen.
    def run_plus4(machine)
      exit_code = Plus4Execution.new(machine).run((cartridge_path if cartridge), dir_abs, prg, budget)
      [exit_code, Testbench.plus4_screen_text(machine)]
    end
  end

  # The 264 testlist's exitcode rows, on the Plus/4 for --plus4 and on
  # the C16 for --c16. Screenshot rows wait for the TED's video, and
  # interactive rows are left out as on the C64. A mountcrt row starts from
  # power-on with its cartridge in, as a C64 cartridge row does.
  module Plus4Testlist
    module_function

    def tests(filters, family, scope: nil, exclude: nil)
      Testlist.numbered(File.readlines(PLUS4_TESTLIST).filter_map { |line| parse(line, family) })
              .select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    def parse(line, family)
      line = line.strip
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless type == "exitcode"

      test = TestCase.new(dir.chomp("/"), prg, type, timeout.to_i, options, Testlist.cartridge(options))
      test.family = family
      test if runnable?(test)
    end

    def runnable?(test)
      return File.exist?(File.join(test.dir_abs, test.prg)) unless test.cartridge

      test.prg.empty? && File.exist?(test.cartridge_path)
    end
  end
end
