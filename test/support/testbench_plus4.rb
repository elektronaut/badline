# frozen_string_literal: true

# Which rows bin/testbench --plus4 and --c16 run, from plus4-testlist.in,
# and the machine each asks for. The machine-driving half is in
# test/support/testbench_plus4_machine.rb, which the Spinel build shares.
module Testbench
  PLUS4_TESTLIST = File.expand_path("../../vendor/VICE-testprogs/testbench/plus4-testlist.in", __dir__)

  # A TestCase's machine, when the row is the 264 series', and its run.
  # The testlist option that asks for a 264's NTSC board.
  TED_NTSC_OPTION = "ted-ntsc"

  module Plus4Row
    def plus4? = %i[plus4 c16].include?(family)

    # The model the row runs on: the family's, its NTSC board for ted-ntsc.
    def plus4_model
      model = family.to_s
      options.include?(TED_NTSC_OPTION) ? "#{model}ntsc" : model
    end

    # The machine the row's tests fork from: booted, or at power-on for a
    # cartridge.
    def plus4_machine = Testbench.plus4_machine(plus4_model, cartridge.nil?)

    # Runs the row on +machine+, returning the exit code and the text
    # screen, or the picture for a screenshot row.
    def run_plus4(machine)
      screenshot = type == "screenshot"
      exit_code = Plus4Execution.new(machine).run(screenshot, (cartridge_path if cartridge), dir_abs, prg, budget)
      [exit_code, screenshot ? Testbench.plus4_screenshot(machine.ted) : Testbench.plus4_screen_text(machine)]
    end
  end

  # A 264 series screenshot against its reference, both cropped as xplus4
  # crops them. VICE's testbench compares them from (32, 35) on, and so
  # does this. An NTSC screenshot, whose window starts 18 lines down
  # where a PAL one's starts 40 down, is compared with a PAL reference on
  # the lines both show, the window's corners lined up. A reference pixel counts as the derived palette's colour
  # nearest to it, so a picture matches as long as each colour the
  # reference shows is nearest to the one badline paints. Colour 0 is
  # black at every luminance, so it counts as index 0 whatever the
  # luminance.
  class Plus4Screenshot
    LEFT = 32
    TOP = 35

    # The line of each screenshot's height the window starts on.
    WINDOW_TOPS = { 288 => 40, 242 => 18 }.freeze

    attr_reader :rows

    def initialize(rows)
      @rows = rows.map { |row| row.map { |index| canonical(index) } }
    end

    # The number of mismatched pixels, or :ref_size.
    def compare(test)
      png = ChunkyPNG::Image.from_file(test.reference)
      return :ref_size unless png.width == rows.first.length && WINDOW_TOPS.key?(png.height)

      shift = WINDOW_TOPS.fetch(png.height) - WINDOW_TOPS.fetch(rows.length)
      cache = {}
      diff = 0
      (TOP...png.height).each do |y|
        row = rows[y - shift]
        next unless row && y >= shift

        (LEFT...png.width).each { |x| diff += 1 unless (cache[png[x, y]] ||= nearest(png[x, y])) == row[x] }
      end
      write_actual(test) if diff.positive?
      diff
    end

    private

    def canonical(index) = index.nobits?(0x0f) ? 0 : index

    def nearest(pixel)
      rgb = [ChunkyPNG::Color.r(pixel), ChunkyPNG::Color.g(pixel), ChunkyPNG::Color.b(pixel)]
      index = (0..127).min_by do |i|
        color = Badline::Chips::TED::PALETTE[i]
        [color >> 16, (color >> 8) & 0xff, color & 0xff].zip(rgb).sum { |a, b| (a - b)**2 }
      end
      canonical(index)
    end

    def write_actual(test)
      png = ChunkyPNG::Image.new(rows.first.length, rows.length)
      rows.each_with_index do |row, y|
        row.each_with_index do |index, x|
          color = Badline::Chips::TED::PALETTE[index]
          png[x, y] = ChunkyPNG::Color.rgb(color >> 16, (color >> 8) & 0xff, color & 0xff)
        end
      end
      png.save(File.join(ARTIFACT_DIR, "#{test.key.tr('/', '-')}.actual.png"))
    end
  end

  # The 264 testlist's exitcode and screenshot rows, on the Plus/4 for
  # --plus4 and on the C16 for --c16, each on its NTSC board with --ntsc,
  # as a ted-ntsc row asks. Interactive rows are left out as on the C64. A mountcrt row starts from
  # power-on with its cartridge in, as a C64 cartridge row does.
  module Plus4Testlist
    module_function

    def tests(filters, family, scope: nil, exclude: nil, ntsc: false)
      Testlist.numbered(File.readlines(PLUS4_TESTLIST).filter_map { |line| parse(line, family, ntsc:) })
              .select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    def parse(line, family, ntsc: false)
      line = line.strip
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless RUNNABLE_TYPES.include?(type)

      options << TED_NTSC_OPTION if ntsc && !options.include?(TED_NTSC_OPTION)

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
