# frozen_string_literal: true

# Which rows bin/testbench --vic20 runs, from vic20-testlist.in, and the
# machine each asks for. The machine-driving half is in
# test/support/testbench_vic20_machine.rb, which the Spinel build shares.
module Testbench
  VIC20_TESTLIST = File.expand_path("../../vendor/VICE-testprogs/testbench/vic20-testlist.in", __dir__)

  # The RAM configuration each memory option asks for, as xvic's -memory
  # fits it: BLK1 for vic20-8k, and every block for vic20-32k, which xvic
  # starts with -memory all. A row with neither, or vic20-unexp, runs
  # unexpanded.
  VIC20_RAM = { "vic20-8k" => :"8k", "vic20-32k" => :all }.freeze

  # A GEO-RAM, which badline doesn't fit to the VIC-20.
  VIC20_SKIP_OPTIONS = /\Ageo512k\z/

  # The testlist options that ask for the NTSC VIC-20 and the PAL one, as
  # xvic's hook names them.
  VIC_NTSC_OPTION = "vic-ntsc"
  VIC_PAL_OPTION = "vic-pal"

  # The row types the VIC-20 runs: the testlist's, and two of badline's
  # own (VIC20_ROWS). Interactive rows are left out, as on the C64.
  VIC20_TYPES = %w[exitcode screenshot dump raster].freeze
  VIC20_MEASURED_TYPES = %w[dump raster].freeze

  # The dump a dump row compares against, in its directory's dumps/, and
  # the bytes at its start that name the program and its revision, which
  # aren't compared: the NTSC timing dumps come from revision R01C, and
  # timing_ntsc.prg is R01N.
  DUMP_OPTION = "dump:"
  DUMP_NAME_LENGTH = 32

  # Rows of badline's own, in the testlist's format, for programs the
  # testlist comments out until a testbench can run them. Each tagged
  # vic-pal runs only on testbench-vic20 and each tagged vic-ntsc only on
  # testbench-vic20-ntsc.
  #
  # A dump row runs a split-tests program and compares the results it
  # leaves at $17E0-$1BFF with a dump of the same program on a real
  # VIC-20 (the program's README.txt names the machines): the 6561E's for
  # timing and lightpen, the 6560-101's for timing_ntsc and the 6560's,
  # wilson's 6560-101, for lightpen_ntsc. A raster row runs raster-ntsc
  # without interlace and, with the interlace option, with it, and
  # compares where the raster effect starts with what its readme says a
  # real NTSC VIC-20 shows (RASTER_POSITIONS).
  VIC20_ROWS = [
    "../VIC20/split-tests/timing/,timing.prg,dump,30000000,#{VIC_PAL_OPTION},#{DUMP_OPTION}dump6561e.prg",
    "../VIC20/split-tests/lightpen/,lightpen.prg,dump,60000000,#{VIC_PAL_OPTION},#{DUMP_OPTION}dump6561e.prg",
    "../VIC20/split-tests/timing/,timing_ntsc.prg,dump,25000000,#{VIC_NTSC_OPTION},#{DUMP_OPTION}dump6560-101.prg",
    "../VIC20/split-tests/lightpen/,lightpen_ntsc.prg,dump,45000000,#{VIC_NTSC_OPTION},#{DUMP_OPTION}dump6560.prg",
    "../VIC20/vic_line0/,raster-ntsc.prg,raster,10000000,#{VIC_NTSC_OPTION}",
    "../VIC20/vic_line0/,raster-ntsc.prg,raster,10000000,#{VIC_NTSC_OPTION},interlace"
  ].freeze

  # Where raster-ntsc's readme says the effect starts at the earliest, in
  # cycles from the window's left edge, in either field: 33 cycles late
  # for $9004 at 0 and on time for 1. With interlace, $9004 at 0 starts
  # on time in one of the two fields.
  RASTER_POSITIONS = {
    false => ["$9004=0: 33 33", "$9004=1: 0 0"],
    true => ["$9004=0: 0 33", "$9004=1: 0 0"]
  }.freeze

  # A TestCase's machine, when the row is the VIC-20's, and its run.
  module Vic20Row
    def vic20? = family == :vic20

    def ram_configuration
      options.filter_map { |option| VIC20_RAM[option] }.first || :unexpanded
    end

    # The model the row runs on: the NTSC one for vic-ntsc, else PAL.
    def vic20_model = options.include?(VIC_NTSC_OPTION) ? "ntsc" : "pal"

    # What Vic20Execution runs: the row's type, raster-interlace for a
    # raster row with interlace.
    def vic20_kind = type == "raster" && options.include?("interlace") ? "raster-interlace" : type

    # Whether the row is scored by vic20_verdict.
    def vic20_measured? = vic20? && VIC20_MEASURED_TYPES.include?(type)

    # The machine the row's tests fork from: booted, or at power-on for a
    # cartridge.
    def vic20_machine = Testbench.vic20_machine(ram_configuration, cartridge.nil?, vic20_model)

    # Runs the row on +machine+, returning the exit code and what the row
    # is scored on (Testbench.vic20_outcome).
    def run_vic20(machine)
      execution = Vic20Execution.new(machine)
      exit_code = execution.run(vic20_kind, (cartridge_path if cartridge), dir_abs, prg, budget)
      [exit_code, Testbench.vic20_outcome(machine, execution, type)]
    end

    # The verdict of a dump or raster row on the lines it left.
    def vic20_verdict(lines)
      return raster_verdict(lines) if type == "raster"

      expected = File.binread(File.join(dir_abs, "dumps", dump_name)).bytes.drop(2 + DUMP_NAME_LENGTH)
      actual = lines.join.scan(/../).map { it.to_i(16) }.drop(DUMP_NAME_LENGTH)
      wrong = actual.each_index.reject { |offset| actual[offset] == expected[offset] }
      return "PASS" if wrong.empty? && actual.length == expected.length

      format("diff=%<count>d bytes from $%<first>04x", count: wrong.length,
                                                       first: VIC20_DUMP + DUMP_NAME_LENGTH +
                                                              (wrong.first || actual.length))
    end

    private

    def dump_name = options.find { it.start_with?(DUMP_OPTION) }.delete_prefix(DUMP_OPTION)

    def raster_verdict(lines)
      expected = RASTER_POSITIONS.fetch(options.include?("interlace"))
      lines == expected ? "PASS" : "positions=#{lines.join(', ')}"
    end
  end

  # What a VIC-20 row is scored on: the display for a screenshot row, the
  # dump's lines for a dump row, the raster effect's positions for a
  # raster row, and the text screen for the others.
  def self.vic20_outcome(machine, execution, type)
    case type
    when "screenshot" then vic20_screenshot(machine)
    when "dump" then vic20_dump(machine)
    when "raster" then execution.positions
    else vic20_screen_text(machine)
    end
  end

  # The VIC-20 testlist's exitcode and screenshot rows and VIC20_ROWS,
  # each on the NTSC VIC-20 with --ntsc, as a vic-ntsc row asks and as
  # VICE's testbench runs xvic with --ntsc. A mountcrt row starts from
  # power-on with its cartridge in, as a C64 cartridge row does.
  module Vic20Testlist
    module_function

    def tests(filters, scope: nil, exclude: nil, ntsc: false)
      lines = File.readlines(VIC20_TESTLIST) + VIC20_ROWS
      Testlist.numbered(lines.filter_map { |line| parse(line, ntsc:) })
              .select { |test| Testlist.selected?(test, filters, scope, exclude) }
    end

    def parse(line, ntsc: false)
      line = line.strip
      return if line.empty? || line.start_with?("#")

      dir, prg, type, timeout, *options = line.split(",")
      return unless VIC20_TYPES.include?(type)
      return if options.any?(VIC20_SKIP_OPTIONS)
      return if options.include?(ntsc ? VIC_PAL_OPTION : VIC_NTSC_OPTION)

      options << VIC_NTSC_OPTION if ntsc && !options.include?(VIC_NTSC_OPTION)

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
  # indices, against the row's reference. xvic's screenshots draw each
  # pixel twice across. VICE's testbench lines a screenshot up with its
  # reference by the top left corner of the KERNAL's text window, at (96,
  # 48) in a PAL one and (40, 22) in an NTSC one, and compares them on the
  # part both show around it: here (48, 48) and (20, 22), each pixel once.
  # A reference pixel goes to the nearest colour of the VIC-I's palette.
  class Vic20Screenshot
    # A view's width and the text window's corner, by its height.
    VIEWS = { 284 => [284, 48, 48], 233 => [260, 20, 22] }.freeze

    attr_reader :rows

    def initialize(rows)
      @rows = rows
    end

    # Returns the number of mismatched pixels, or :ref_size for a
    # reference of a size no VIC-20 screenshot has, and writes the
    # screenshot for a mismatch.
    def compare(test)
      reference = ReferenceImage.new(test.reference, Badline::Chips::VICI::PALETTE)
      width, height = reference.size
      view = VIEWS[height]
      return :ref_size unless view && width == 2 * view[0]

      diff = count_mismatches(reference, view, VIEWS.fetch(rows.length))
      write_actual(test) if diff.positive?
      diff
    end

    private

    def count_mismatches(reference, (ref_width, ref_x, ref_y), (_width, x0, y0))
      left = [ref_x, x0].min
      top = [ref_y, y0].min
      across = left + [ref_width - ref_x, rows.first.length - x0].min
      down = top + [reference.size[1] - ref_y, rows.length - y0].min
      down.times.sum do |y|
        expected = reference.row(y - top + ref_y)
        actual = rows[y - top + y0]
        across.times.count { |x| expected[2 * (x - left + ref_x)] != actual[x - left + x0] }
      end
    end

    def write_actual(test)
      palette = Badline::Chips::VICI::PALETTE
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
