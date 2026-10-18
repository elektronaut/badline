# frozen_string_literal: true

# Which rows bin/testbench --cbm2 and --cbm5x0 run, from cbm610-testlist.in
# and cbm510-testlist.in, and the machine each asks for. The machine-driving
# halves are in test/support/testbench_cbm2_machine.rb and
# test/support/testbench_p500_machine.rb, which the Spinel builds share.
module Testbench
  # The testlist each family runs, and the model the hooks start xcbm2 and
  # xcbm5x0 as.
  CBM2_TESTLISTS = {
    cbm2: File.expand_path("../../vendor/VICE-testprogs/testbench/cbm610-testlist.in", __dir__),
    cbm5x0: File.expand_path("../../vendor/VICE-testprogs/testbench/cbm510-testlist.in", __dir__)
  }.freeze
  CBM2_MODELS = { cbm2: "610", cbm5x0: "510" }.freeze

  # A row the testlist doesn't have: the pass program from the selftest's
  # .d82, which the 610 loads from device 8 through the traps on its
  # IEEE-488 primitives.
  CBM2_DISK_ROW = "./selftest/,cbm610-pass.d82,exitcode,100000000"

  # Commodore's burn-in disk, which the testlist runs interactively: graded
  # by its grid of chips once it has tested each of them
  # (CBM2Execution#burnin_grade).
  CBM2_BURNIN_ROW = "../CBM2/,cbm2-burnin.d80,exitcode,75000000"

  # A TestCase's machine, when the row is the CBM-II's, and its run.
  module CBM2Row
    def cbm2? = CBM2_MODELS.key?(family)

    # Whether the row is the P500's, --cbm5x0's.
    def p500? = family == :cbm5x0

    def cbm2_model = CBM2_MODELS.fetch(family)

    # The machine the row's tests fork from: booted, or at power-on for a
    # cartridge.
    def cbm2_machine
      return Testbench.p500_machine(cbm2_model, cartridge.nil?) if p500?

      Testbench.cbm2_machine(cbm2_model, cartridge.nil?)
    end

    # Runs the row on +machine+, returning the exit code and the text
    # screen, or the picture for a screenshot row.
    def run_cbm2(machine)
      return run_p500(machine) if p500?

      screenshot = type == "screenshot"
      exit_code = CBM2Execution.new(machine).run(screenshot, (cartridge_path if cartridge), dir_abs, prg, budget)
      [exit_code, screenshot ? Testbench.cbm2_screenshot(machine) : Testbench.cbm2_screen_text(machine)]
    end

    # A P500's run, whose picture is the VIC-II's, cropped as xcbm5x0's
    # screenshots are, as a C64's is.
    def run_p500(machine)
      screenshot = type == "screenshot"
      exit_code = P500Execution.new(machine).run(screenshot, (cartridge_path if cartridge), dir_abs, prg, budget)
      [exit_code, screenshot ? Testbench.screenshot(machine.vic) : Testbench.p500_screen_text(machine)]
    end
  end

  # A CBM-II screenshot against its reference. VICE's testbench compares
  # the two from (32, 35) on, over the lines and dots both have, and so
  # does this. A reference dot counts as lit where it is more green than
  # not.
  class CBM2Screenshot
    LEFT = 32
    TOP = 35

    attr_reader :rows

    def initialize(rows)
      @rows = rows
    end

    # The number of mismatched dots.
    def compare(test)
      png = ChunkyPNG::Image.from_file(test.reference)
      width = [png.width, rows.first.length].min
      diff = 0
      (TOP...[png.height, rows.length].min).each do |y|
        row = rows[y]
        (LEFT...width).each { |x| diff += 1 unless (ChunkyPNG::Color.g(png[x, y]) > 0x80 ? 1 : 0) == row[x] }
      end
      write_actual(test) if diff.positive?
      diff
    end

    private

    def write_actual(test)
      png = ChunkyPNG::Image.new(rows.first.length, rows.length)
      rows.each_with_index do |row, y|
        row.each_with_index do |index, x|
          color = Badline::PET::Canvas::PALETTE[index]
          png[x, y] = ChunkyPNG::Color.rgb(color >> 16, (color >> 8) & 0xff, color & 0xff)
        end
      end
      png.save(File.join(ARTIFACT_DIR, "#{test.key.tr('/', '-')}.actual.png"))
    end
  end

  # The CBM-II testlists' exitcode and screenshot rows, on the 610 for
  # --cbm2 and the 510 for --cbm5x0, and on the 610 CBM2_DISK_ROW and
  # CBM2_BURNIN_ROW. Interactive rows are left out as on the C64. A
  # mountcrt row starts from power-on with its cartridge in.
  module CBM2Testlist
    module_function

    def tests(filters, family, scope: nil, exclude: nil)
      lines = File.readlines(CBM2_TESTLISTS.fetch(family))
      lines.push(CBM2_DISK_ROW, CBM2_BURNIN_ROW) if family == :cbm2
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
