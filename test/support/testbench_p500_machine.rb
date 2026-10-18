# frozen_string_literal: true

require_relative "testbench_machine"

# The machine-driving half of bin/testbench --cbm5x0: building the P500 a
# row asks for, loading its program into BASIC's text segment, running it
# until it reports through $DAFF or its budget runs out, and reading back
# the text screen or the picture. It stays inside the Ruby subset Spinel
# compiles, so bin/testbench on CRuby and spinel/p500_testbench.rb on a
# Spinel build run each test the same way.
module Testbench
  P500_SCREEN = 0xd000

  # A P500 of +model+ (Badline::CBM2::P500::Model::ALL), booted up to the
  # cycle where a program loads, or left at power-on when +boot+ is false,
  # for a cartridge that has to be in before the first cycle.
  def self.p500_machine(model, boot)
    machine = Badline::CBM2::P500.new(model:)
    machine.run_cycles(machine.init_threshold) if boot
    machine
  end

  # The text screen in the static video matrix at $D000 of segment 15, 25
  # lines of 40 characters.
  def self.p500_screen_text(machine)
    screen = machine.bus.screen
    Array.new(25) { |row| screen_line(screen, P500_SCREEN + (row * 40), 40) }
  end

  # Runs one test on a machine from Testbench.p500_machine: puts the
  # cartridge's ROM chips, if any, in at power-on, loads the program, if
  # any, then runs until the test writes $DAFF or the budget runs out. Only
  # a screenshot test reads the picture, so the others run with it
  # unpainted.
  class P500Execution
    # BASIC's segment for its text, and where in segment 15 BASIC keeps
    # TXTTAB and the end of the text, and the KERNAL EAL and its segment,
    # as on the B series.
    TEXT_SEGMENT = 0
    TXTTAB = 0x2d
    TEXT_END = 0x2f
    EAL = 0x96

    attr_reader :exit_code

    def initialize(machine)
      @machine = machine
      @exit_code = nil
      machine.install_debug_register { |value| @exit_code = value }
    end

    def run(render, cartridge, directory, prg, budget)
      @machine.vic.render = render
      @machine.attach_cartridge(Badline::Storage::CRTFile.new(cartridge, machine: :cbm2).chips) if cartridge
      basic_load(File.binread(File.join(directory, prg)).bytes) unless prg.empty?
      @machine.run_until(budget) { @exit_code }
      @exit_code
    end

    private

    # The program goes to the start of BASIC's text in segment 0, whatever
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
