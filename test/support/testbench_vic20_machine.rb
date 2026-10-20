# frozen_string_literal: true

require_relative "testbench_machine"

# The machine-driving half of bin/testbench --vic20: building the VIC-20 a
# row asks for, loading its program as xvic's -basicload does, running it
# until it reports through $910F or its budget runs out, and reading back
# what the row is scored on: the text screen, the display, the dump a
# split-tests program leaves in RAM, or the raster effect's position. It
# stays inside the Ruby subset Spinel compiles, so bin/testbench on CRuby
# and spinel/vic20_testbench.rb on a Spinel build run each test the same
# way.
module Testbench
  # Where a split-tests program keeps its results, $17C0-$1BFF, the byte
  # of it the program writes last, its stability count, and how many bytes
  # a line of the dump's text holds.
  VIC20_DUMP = 0x17c0
  VIC20_DUMP_LENGTH = 0x440
  VIC20_DUMP_DONE = 0x17e8
  VIC20_DUMP_LINE = 64

  # A VIC-20 of +model+ (Badline::Vic20::MODELS) with the RAM expansion
  # +ram+ names (Badline::Vic20::Bus::RAM_CONFIGURATIONS), booted up to the
  # cycle where a program loads, or left at power-on when +boot+ is false,
  # for a cartridge that has to be in before the first cycle. The VIC
  # paints its display only once a run asks it to.
  def self.vic20_machine(ram, boot, model)
    machine = Badline::Vic20.new(ram:, model:)
    machine.vic.render = false
    machine.run_cycles(machine.init_threshold) if boot
    machine
  end

  # The text screen where the KERNAL keeps it, at the page in $0288, 23
  # lines of 22 characters, or blank lines before the KERNAL has set it.
  def self.vic20_screen_text(machine)
    ram = machine.ram
    screen = ram.peek(0x0288) << 8
    return Array.new(23) { "" } if screen >= 0x2000

    Array.new(23) { |row| screen_line(ram, screen + (row * 22), 22) }
  end

  # The display cropped to the machine's view, xvic's, as rows of palette
  # indices.
  def self.vic20_screenshot(machine)
    vic = machine.vic
    crop = machine.timing.crop
    display = vic.display
    width = vic.width
    Array.new(crop[3]) { |row| display[((crop[1] + row) * width) + crop[0], crop[2]] }
  end

  # The split-tests results, $17C0-$1BFF, as lines of hex digits.
  def self.vic20_dump(machine)
    ram = machine.ram
    Array.new(VIC20_DUMP_LENGTH / VIC20_DUMP_LINE) do |line|
      text = +""
      VIC20_DUMP_LINE.times do |offset|
        value = ram.peek(VIC20_DUMP + (line * VIC20_DUMP_LINE) + offset)
        text << Record::HEX_DIGITS[value >> 4] << Record::HEX_DIGITS[value & 0x0f]
      end
      text
    end
  end

  # Runs one test on a machine from Testbench.vic20_machine: puts the
  # cartridge's ROM chips, if any, into their blocks, loads the program, if
  # any, then runs until the test writes $910F or the budget runs out. As
  # with VICE's debug cartridge, the run ends on the cycle of the write.
  # Only a screenshot or raster test has the VIC paint its display.
  #
  # A dump test, one of the split-tests programs, runs until the program
  # has written its stability count, the last of its results. A raster test
  # runs vic_line0's raster-ntsc (RasterNTSC).
  class Vic20Execution
    attr_reader :exit_code, :positions

    def initialize(machine)
      @machine = machine
      @exit_code = nil
      @positions = []
      machine.install_debug_register { |value| @exit_code = value }
    end

    def run(type, cartridge, directory, prg, budget)
      raster = type.start_with?("raster")
      @machine.vic.render = raster || type == "screenshot"
      insert(cartridge) if cartridge
      return run_raster(directory, prg, budget, type) if raster

      basic_load(File.binread(File.join(directory, prg)).bytes, "") unless prg.empty?
      if type == "dump"
        @machine.ram.write(VIC20_DUMP_DONE, [0])
        @machine.run_until(budget) { !@machine.ram.peek(VIC20_DUMP_DONE).zero? }
      else
        @machine.run_until(budget) { !@exit_code.nil? }
      end
      @exit_code
    end

    private

    def run_raster(directory, prg, budget, type)
      interlace = type == "raster-interlace"
      basic_load(File.binread(File.join(directory, prg)).bytes, interlace ? "y" : "n")
      @positions = RasterNTSC.new(@machine).measure(budget)
      nil
    end

    def insert(path)
      Badline::Storage::CRTFile.new(path, machine: :vic20).chips.each do |chip|
        @machine.bus.map_rom(chip.address, chip.data)
      end
    end

    # As xvic's -basicload: the program goes to the start of BASIC, whatever
    # its load address, BASIC's end of program and the KERNAL's end address
    # are set as LOAD sets them, and RUN goes into the keyboard buffer,
    # with +keys+ after it.
    def basic_load(data, keys)
      ram = @machine.ram
      start = ram.peek16(0x2b)
      ram.write(start, data[2..])
      finish = start + data.length - 2
      [0x2d, 0xae].each { |pointer| ram.write(pointer, [finish & 0xff, finish >> 8]) }
      @machine.type_text("run\r#{keys}")
    end
  end

  # VIC20/vic_line0/raster-ntsc, which waits for $9004 to read a value,
  # then a fixed time, and turns the background black and the border
  # purple for a few cycles, at a random delay of a few cycles from field
  # to field. The answer typed after RUN, n or y, turns interlace off or
  # on, and SPACE steps the value it waits for, from 0. Its readme says
  # where a real NTSC VIC-20 starts the effect at the earliest, in cycles
  # from the text window's left edge, as the program's ruler counts them.
  #
  # This finds that for $9004 at 0 and at 1, over fields of each, on the
  # blank top row of the text window, the earliest of the even fields and
  # of the odd ones. Each value's line reads "$9004=V: EVEN ODD", the lower
  # first.
  class RasterNTSC
    FIELDS = 64

    # The line each field is scanned on, below the row the effect lands
    # on, and the colours of the effect: the background black, the border
    # purple.
    SCAN_LINE = 120
    EFFECT_COLORS = [0, 4].freeze

    # The address the program compares $9004 with.
    VALUE = 0x0342

    # A field without the effect, and the pixels the VIC draws a cycle.
    NONE = -1000
    PIXELS = Badline::Chips::VICI::PIXELS_PER_CYCLE

    # When the program is waiting for the value to start over, after RUN
    # has read the program's machine code into place.
    SETTLE_CYCLES = 3_000_000

    def initialize(machine)
      @machine = machine
      @vic = machine.vic
    end

    def measure(budget)
      @machine.run_cycles(SETTLE_CYCLES)
      lines = [value_line(0)]
      press_space(budget)
      lines << value_line(1)
      lines
    end

    private

    def value_line(value)
      earliest = [NONE, NONE]
      2.times { next_field }
      FIELDS.times do |field|
        next_field
        position = effect_position
        parity = field % 2
        earliest[parity] = position if position != NONE && (earliest[parity] == NONE || position < earliest[parity])
      end
      "$9004=#{value}: #{earliest.min} #{earliest.max}"
    end

    # Holds SPACE until BASIC has moved on to the next value.
    def press_space(budget)
      keyboard = @machine.keyboard
      keyboard.press(:space)
      @machine.run_until(budget) { @machine.ram.peek(VALUE) != 0 }
      keyboard.release(:space)
    end

    # Runs on to the scan line of the next field.
    def next_field
      cycles = @vic.profile.cycles_per_line
      @machine.run_cycles(cycles)
      @machine.run_cycles(cycles) until @vic.rasterline == SCAN_LINE
    end

    # The effect's first pixel on the window's top row, in whole cycles
    # from the window's left edge, or NONE without one.
    def effect_position
      display = @vic.display
      width = @vic.width
      registers = @vic.register_file
      top = registers[1] * 2
      first = width
      8.times do |row|
        base = (top + row) * width
        x = 0
        while x < first
          first = x if EFFECT_COLORS.include?(display[base + x])
          x += 1
        end
      end
      return NONE if first == width

      pixels = first - ((registers[0] & 0x7f) * PIXELS)
      pixels.negative? ? -((PIXELS - 1 - pixels) / PIXELS) : pixels / PIXELS
    end
  end
end
