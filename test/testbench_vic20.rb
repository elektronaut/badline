# frozen_string_literal: true

# Which rows bin/testbench --vic20 runs, from vic20-testlist.in, and the
# machine each asks for. The machine-driving half is in
# test/testbench_vic20_machine.rb, which the Spinel build shares.
module Testbench
  VIC20_TESTLIST = File.expand_path("../vendor/VICE-testprogs/testbench/vic20-testlist.in", __dir__)

  # The RAM configuration each memory option asks for, as xvic's -memory
  # fits it: BLK1 for vic20-8k, and every block for vic20-32k, which xvic
  # starts with -memory all. A row with neither, or vic20-unexp, runs
  # unexpanded.
  VIC20_RAM = { "vic20-8k" => :"8k", "vic20-32k" => :all }.freeze

  # The row types the VIC-20 runs. Interactive rows are left out, as on
  # the C64.
  VIC20_TYPES = %w[exitcode screenshot].freeze

  # A GEO-RAM, which badline doesn't fit to the VIC-20.
  VIC20_SKIP_OPTIONS = /\Ageo512k\z/

  # A TestCase's machine, when the row is the VIC-20's, and its run.
  module Vic20Row
    def vic20? = family == :vic20

    # The row's display, +rows+ of palette indices, to compare against its
    # reference.
    def screenshot_of(rows) = vic20? ? Vic20Screenshot.new(rows) : Screenshot.new(rows)

    def ram_configuration
      options.filter_map { |option| VIC20_RAM[option] }.first || :unexpanded
    end

    # The machine the row's tests fork from: booted, or at power-on for a
    # cartridge.
    def vic20_machine = Testbench.vic20_machine(ram_configuration, cartridge.nil?)

    # Runs the row on +machine+, returning the exit code and the text
    # screen, or the display for a screenshot row.
    def run_vic20(machine)
      screenshot = type == "screenshot"
      exit_code = Vic20Execution.new(machine).run(screenshot, (cartridge_path if cartridge), dir_abs, prg, budget)
      [exit_code, screenshot ? Testbench.vic20_screenshot(machine) : Testbench.vic20_screen_text(machine)]
    end
  end

  # The VIC-20 testlist's exitcode and screenshot rows. A mountcrt row
  # starts from power-on with its cartridge in, as a C64 cartridge row
  # does.
  module Vic20Testlist
    module_function

    def tests(filters, scope: nil, exclude: nil)
      Testlist.numbered(File.readlines(VIC20_TESTLIST).filter_map { |line| parse(line) })
              .select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    def parse(line)
      line = line.strip
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless VIC20_TYPES.include?(type)
      return if options.any?(VIC20_SKIP_OPTIONS)

      test = TestCase.new(dir.chomp("/"), prg, type, timeout.to_i, options, Testlist.cartridge(options))
      test.family = :vic20
      test if runnable?(test)
    end

    def runnable?(test)
      return File.exist?(File.join(test.dir_abs, test.prg)) unless test.cartridge

      test.prg.empty? && File.exist?(test.cartridge_path)
    end
  end

  # A VIC-20 screenshot, the display in xvic's view as rows of palette
  # indices, against the row's reference. xvic's references draw each pixel
  # twice across, and VICE compares them from (96, 48), the top left corner
  # of the KERNAL's text window: (48, 48) here. A reference pixel goes to
  # the nearest colour of the VIC-I's palette.
  class Vic20Screenshot
    LEFT = 48
    TOP = 48

    attr_reader :rows

    def initialize(rows)
      @rows = rows
    end

    # Returns the number of mismatched pixels, or :ref_size for a
    # reference of another size, and writes failure artifacts.
    def compare(test)
      reference = ReferenceImage.new(test.reference, Badline::Vic20::VIC::PALETTE)
      width, height = reference.size
      return :ref_size unless width == 2 * rows.first.length && height == rows.length

      expected = Array.new(height) { |y| reference.row(y).each_slice(2).map(&:first) }
      diff = (TOP...height).sum { |y| (LEFT...rows[y].length).count { |x| expected[y][x] != rows[y][x] } }
      write_artifact(test) if diff.positive?
      diff
    end

    private

    def write_artifact(test)
      palette = Badline::Vic20::VIC::PALETTE
      png = ChunkyPNG::Image.new(2 * rows.first.length, rows.length)
      rows.each_with_index do |row, y|
        row.each_with_index do |index, x|
          rgb = palette[index]
          color = ChunkyPNG::Color.rgb(rgb >> 16, (rgb >> 8) & 0xff, rgb & 0xff)
          png[2 * x, y] = color
          png[(2 * x) + 1, y] = color
        end
      end
      png.save(File.join(ARTIFACT_DIR, "#{test.key.tr('/', '-')}.actual.png"))
    end
  end
end
