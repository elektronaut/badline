# frozen_string_literal: true

require_relative "testbench_machine"

# The machine-driving half of bin/testbench --plus4 and --c16: building the
# 264 series machine a row asks for, loading its program as xvic's
# -basicload does on the VIC-20, running it until it reports through $FDCF
# or its budget runs out, and reading back the text screen. It stays
# inside the Ruby subset Spinel compiles, so bin/testbench on CRuby and
# spinel/plus4_testbench.rb on a Spinel build run each test the same way.
module Testbench
  PLUS4_SCREEN = 0x0c00

  # xplus4's screenshots: 384 by 288 lines from line 276 on PAL, which puts
  # the display window's top left corner at (32, 40), and 384 by 242 from
  # line 248 on NTSC, which puts it at (32, 18).
  PLUS4_PAL_VIEW = [276, 288].freeze
  PLUS4_NTSC_VIEW = [248, 242].freeze

  # A 264 series machine of +model+ with a 1551's TCBM interface plugged
  # in, as xplus4 starts with a 1551 as drive 8, booted up to the cycle
  # where a program loads, or left at power-on when +boot+ is false, for a
  # cartridge that has to be in before the first cycle.
  def self.plus4_machine(model, boot)
    machine = Badline::Plus4.new(model:, tcbm: true)
    machine.run_cycles(machine.init_threshold) if boot
    machine
  end

  # The TED's picture cropped to xplus4's screenshot, as rows of palette
  # indices.
  def self.plus4_screenshot(ted)
    display = ted.display
    width = ted.width
    lines = ted.height
    top, height = lines == 312 ? PLUS4_PAL_VIEW : PLUS4_NTSC_VIEW
    Array.new(height) { |row| display[((row + top) % lines) * width, width] }
  end

  # The text screen at $0C00, 25 lines of 40 characters.
  def self.plus4_screen_text(machine)
    ram = machine.ram
    Array.new(25) { |row| screen_line(ram, PLUS4_SCREEN + (row * 40), 40) }
  end

  # Runs one test on a machine from Testbench.plus4_machine: puts the
  # cartridge's ROM chips, if any, into cartridge 1's slots, loads the
  # program, if any, then runs until the test writes $FDCF or the budget
  # runs out, the cycle of the write ending the run as on the C64. Only a
  # screenshot test reads the picture, so the others run with the TED's
  # picture unpainted.
  class Plus4Execution
    attr_reader :exit_code

    def initialize(machine)
      @machine = machine
      @exit_code = nil
      machine.install_debug_register { |value| @exit_code = value }
    end

    def run(render, cartridge, directory, prg, budget)
      @machine.ted.render = render
      @machine.attach_cartridge(Badline::Storage::CRTFile.new(cartridge, machine: :plus4).chips) if cartridge
      basic_load(File.binread(File.join(directory, prg)).bytes) unless prg.empty?
      @machine.run_until(budget) { @exit_code }
      @exit_code
    end

    private

    # The program goes to the start of BASIC at TXTTAB, whatever its load
    # address, BASIC's end of program at VARTAB and the KERNAL's end
    # address at EAL are set as LOAD sets them, and RUN goes into the
    # keyboard buffer.
    def basic_load(data)
      ram = @machine.ram
      start = ram.peek16(0x2b)
      ram.write(start, data[2..])
      finish = start + data.length - 2
      [0x2d, 0x9d].each { |pointer| ram.write(pointer, [finish & 0xff, finish >> 8]) }
      @machine.type_text("run\r")
    end
  end
end
