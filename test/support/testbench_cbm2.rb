# frozen_string_literal: true

# Which rows bin/testbench --cbm2 and --cbm5x0 run, from cbm610-testlist.in
# and cbm510-testlist.in, and the machine each asks for.
module Testbench
  # The testlist each family runs, and the model the hooks start xcbm2 and
  # xcbm5x0 as.
  CBM2_TESTLISTS = {
    cbm2: File.expand_path("../../vendor/VICE-testprogs/testbench/cbm610-testlist.in", __dir__),
    cbm5x0: File.expand_path("../../vendor/VICE-testprogs/testbench/cbm510-testlist.in", __dir__)
  }.freeze
  CBM2_MODELS = { cbm2: "610", cbm5x0: "510" }.freeze

  # A TestCase's machine, when the row is the CBM-II's.
  module CBM2Row
    def cbm2? = CBM2_MODELS.key?(family)

    def cbm2_model = CBM2_MODELS.fetch(family)

    def cbm2_machine = Badline::CBM2.new(model: cbm2_model)
  end

  # The CBM-II testlists' exitcode and screenshot rows, on the 610 for
  # --cbm2 and the 510 for --cbm5x0. Interactive rows are left out as on
  # the C64. A mountcrt row starts from power-on with its cartridge in.
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
      return unless RUNNABLE_TYPES.include?(type)

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
