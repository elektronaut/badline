# frozen_string_literal: true

require_relative "testbench_machine"

# The machine-driving half of bin/testbench --cbm2: building the CBM-II a
# row asks for, loading its program into BASIC's text segment, running it
# until it reports through $DAFF or its budget runs out, and reading back
# the text screen or the picture. It stays inside the Ruby subset Spinel compiles, so
# bin/testbench on CRuby and spinel/cbm2_testbench.rb on a Spinel build
# run each test the same way.
module Testbench
  CBM2_SCREEN = 0xd000

  # A CBM-II of +model+ (Badline::CBM2::Model::ALL), booted up to the
  # cycle where a program loads, or left at power-on when +boot+ is false,
  # for a cartridge that has to be in before the first cycle.
  def self.cbm2_machine(model, boot)
    machine = Badline::CBM2.new(model:)
    machine.run_cycles(machine.init_threshold) if boot
    machine
  end

  # The text screen at $D000 of segment 15, 25 lines of 80 characters.
  def self.cbm2_screen_text(machine)
    screen = machine.bus.screen
    Array.new(25) { |row| screen_line(screen, CBM2_SCREEN + (row * 80), 80) }
  end

  # The picture, its rows of palette indices, as xcbm2's screenshots frame
  # it.
  def self.cbm2_screenshot(machine)
    canvas = machine.video
    display = canvas.display
    width = canvas.width
    Array.new(canvas.height) { |row| display[row * width, width] }
  end

  # Runs one test on a machine from Testbench.cbm2_machine: puts the
  # cartridge's ROM chips, if any, in at power-on, loads the program, if
  # any, then runs until the test writes $DAFF or the budget runs out. Only
  # a screenshot test reads the picture, so the others run with it
  # unpainted.
  #
  # A .d80 is Commodore's burn-in disk: its test loads and runs, and once
  # the budget runs out the grid of chips it draws is graded, exit code
  # $00 for every one of BURNIN_CELLS cells OK and none BAD, $FF otherwise.
  class CBM2Execution
    # BASIC's segment for its text, and where in segment 15 BASIC keeps
    # TXTTAB and the end of the text, and the KERNAL EAL and its segment.
    TEXT_SEGMENT = 1
    TXTTAB = 0x2d
    TEXT_END = 0x2f
    EAL = 0x96

    # What the burn-in disk's instructions say to type, and the chips and
    # RAM banks its grid grades on a 128K B series.
    BURNIN = %(dload"b-128/256 test"\rrun\r)
    BURNIN_CELLS = 47

    attr_reader :exit_code

    def initialize(machine)
      @machine = machine
      @exit_code = nil
      machine.install_debug_register { |value| @exit_code = value }
    end

    def run(render, cartridge, directory, prg, budget)
      @machine.crtc_video.render = render
      @machine.attach_cartridge(Badline::Storage::CRTFile.new(cartridge, machine: :cbm2).chips) if cartridge
      load(File.join(directory, prg)) unless prg.empty?
      @machine.run_until(budget) { @exit_code }
      @exit_code = burnin_grade if prg.end_with?(".d80")
      @exit_code
    end

    private

    # A .d82 mounts as device 8 through the traps, and its first program
    # loads and runs as Media does. Any other file is a program.
    def load(path)
      return burnin_load(path) if path.end_with?(".d80")
      return basic_load(File.binread(path).bytes) unless path.end_with?(".d82")

      @machine.mount(Badline::Storage::D82Image.new(path, read_only: true))
      @machine.type_text(Badline::Media::CBM2Media::AUTOSTART)
    end

    def burnin_load(path)
      @machine.mount(Badline::Storage::D80Image.new(path, read_only: true))
      @machine.type_text(BURNIN)
    end

    # $00 when the grid holds BURNIN_CELLS "OK" and no "BAD", in screen
    # codes on the 80-column screen at $D000.
    def burnin_grade
      screen = @machine.bus.screen
      text = Array.new(2000) { |offset| screen.peek(0xd000 + offset) & 0x7f }
      ok = 0
      bad = 0
      index = 0
      while index < 1998
        ok += 1 if text[index] == 0x0f && text[index + 1] == 0x0b
        bad += 1 if text[index] == 0x02 && text[index + 1] == 0x01 && text[index + 2] == 0x04
        index += 1
      end
      ok == BURNIN_CELLS && bad.zero? ? 0x00 : 0xff
    end

    # The program goes to the start of BASIC's text in segment 1, whatever
    # its load address, BASIC's end of text and the KERNAL's end address
    # are set as LOAD sets them, and RUN goes into the keyboard buffer.
    def basic_load(data)
      bus = @machine.bus
      start = bus.peek_bank(15, TXTTAB) | (bus.peek_bank(15, TXTTAB + 1) << 8)
      body = data[2..] || []
      body.each_with_index { |byte, i| bus.poke_bank(TEXT_SEGMENT, start + i, byte) }
      finish = start + body.length
      [TEXT_END, EAL].each do |pointer|
        bus.poke_bank(15, pointer, finish & 0xff)
        bus.poke_bank(15, pointer + 1, finish >> 8)
      end
      bus.poke_bank(15, EAL + 2, TEXT_SEGMENT)
      @machine.type_text("run\r")
    end
  end
end
