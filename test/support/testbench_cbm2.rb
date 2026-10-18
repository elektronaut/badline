# frozen_string_literal: true

# Which rows bin/testbench --cbm2 and --cbm5x0 run, from cbm610-testlist.in
# and cbm510-testlist.in, and the machine each asks for. The machine-driving
# half is in test/support/testbench_cbm2_machine.rb, which the Spinel build
# shares.
module Testbench
  # The testlist each family runs, and the model the hooks start xcbm2 and
  # xcbm5x0 as.
  CBM2_TESTLISTS = {
    cbm2: File.expand_path("../../vendor/VICE-testprogs/testbench/cbm610-testlist.in", __dir__),
    cbm5x0: File.expand_path("../../vendor/VICE-testprogs/testbench/cbm510-testlist.in", __dir__)
  }.freeze
  CBM2_MODELS = { cbm2: "610", cbm5x0: "510" }.freeze

  # A TestCase's machine, when the row is the CBM-II's, and its run.
  module CBM2Row
    def cbm2? = CBM2_MODELS.key?(family)

    def cbm2_model = CBM2_MODELS.fetch(family)

    # The machine the row's tests fork from: booted, or at power-on for a
    # cartridge.
    def cbm2_machine = Testbench.cbm2_machine(cbm2_model, cartridge.nil?)

    # Runs the row on +machine+, returning the exit code and the text
    # screen.
    def run_cbm2(machine)
      exit_code = CBM2Execution.new(machine).run((cartridge_path if cartridge), dir_abs, prg, budget)
      [exit_code, Testbench.cbm2_screen_text(machine)]
    end
  end

  # The CBM-II testlists' rows, on the 610 for --cbm2 and the 510 for
  # --cbm5x0: the 610's exitcode rows, its screenshot rows waiting for the
  # B series' video, and the 510's exitcode and screenshot rows, which
  # only --list takes until the P500 runs. Interactive rows are left out
  # as on the C64. A mountcrt row starts from power-on with its cartridge
  # in.
  module CBM2Testlist
    module_function

    def tests(filters, family, scope: nil, exclude: nil)
      lines = File.readlines(CBM2_TESTLISTS.fetch(family))
      Testlist.numbered(lines.filter_map { |line| parse(line, family) })
              .select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    def parse(line, family)
      line = line.strip
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless type == "exitcode" || (type == "screenshot" && family == :cbm5x0)

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
