# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/p500_boot"

describe Badline::CBM2::P500 do
  # A machine whose CPU loops at $0400 of segment 15 with interrupts off,
  # out of the KERNAL's way.
  def looping(**)
    machine = described_class.new(**)
    [0x4c, 0x00, 0x04].each_with_index { |byte, i| machine.poke(0x0400 + i, byte) }
    machine.cpu.program_counter = 0x0400
    machine
  end

  it "is the PAL 510 at 50 Hz by default, and the NTSC one at 60 Hz" do
    machines = [described_class.new, described_class.new(model: "510ntsc")]
    expect(machines.map { |machine| [machine.model.name, machine.timing.clock_hz, machine.mains_hz] })
      .to eq([["510", 985_248, 50], ["510ntsc", 1_022_727, 60]])
  end

  it "refuses a model or a mains it doesn't know" do
    aggregate_failures do
      expect { described_class.new(model: "610") }.to raise_error(ArgumentError, /no P500 model/)
      expect { described_class.new(mains_hz: 55) }.to raise_error(ArgumentError, /50 or 60/)
    end
  end

  it "is what Machine.build makes of the CBM-II's 510" do
    expect(Badline::Machine.build(:cbm2, model: "510ntsc").model.name).to eq("510ntsc")
  end

  it "names its model, RAM and mains for the pause menu" do
    expect(described_class.new(mains_hz: 60).model_label).to eq("510, 128K RAM, 60 HZ")
  end

  it "fills segments 0 and 1" do
    filled = described_class.new.bus.segment_ram.each_with_index.filter_map { |memory, segment| segment if memory }
    expect(filled).to eq([0, 1])
  end

  it "reads the character ROM at $C000 of segment 15" do
    expect(described_class.new.peek(0xc008)).to eq(Badline::ROM.read("character.rom")[8])
  end

  it "keeps the screen in the 1K static video matrix at $D000" do
    machine = described_class.new
    machine.poke(0xd3ff, 0x51)
    expect([machine.peek(0xd3ff), machine.bus.screen.peek(0xd3ff)]).to eq([0x51, 0x51])
  end

  # xcbm5x0 reads the colour RAM's high four bits as 0.
  it "keeps four bits a cell in the colour RAM at $D400, the high four reading 0" do
    machine = described_class.new
    machine.poke(0xd7ff, 0xa7)
    expect(machine.peek(0xd7ff)).to eq(0x07)
  end

  it "repeats the VIC's registers over $D800-$D8FF" do
    machine = described_class.new
    machine.poke(0xd860, 0x05)
    expect(machine.vic.register_file[0x20]).to eq(0x05)
  end

  it "loads a program into BASIC's text in segment 0" do
    machine = described_class.new
    machine.load_prg([0x03, 0x00, 0x0b, 0x00])
    expect([machine.bus.peek_bank(0, 0x0003), machine.bus.peek_bank(1, 0x0003)]).to eq([0x0b, 0x00])
  end

  it "traps the IEEE-488 primitives of 901234-02" do
    expect(described_class.new.trap_layout.talk).to eq(0xf237)
  end

  it "calls the debug register's handler with a write to $DAFF" do
    machine = described_class.new
    codes = []
    machine.install_debug_register { |code| codes << code }
    machine.poke(0xdaff, 0xff)
    expect(codes).to eq([0xff])
  end

  describe "the VIC's view" do
    subject(:machine) { described_class.new }

    let(:bank) { machine.vic.vic_bank }

    before do
      4.times { |quarter| machine.bus.poke_bank(0, (quarter * 0x4000) + 0x1234, 0x10 + quarter) }
      machine.poke(0xd234, 0x99)
    end

    # STATVID and VICDOTSEL are high from the reset, and the bank lines
    # float high until TPI2 drives them.
    it "reads the character ROM in phi1 and the static matrix in phi2 from the reset" do
      expect([bank.peek(0x0008), bank.peek_phi2(0x1234)]).to eq([Badline::ROM.read("character.rom")[8], 0x99])
    end

    it "reads 0 in phi2 with STATVID high and VA12 low" do
      expect(bank.peek_phi2(0x0234)).to eq(0)
    end

    # TPI1's CA and CB low, in mode 1, and TPI2's PC6 and PC7 outputs.
    # Matches xcbm5x0 with each of the four banks filled apart.
    it "reads segment 0 in both halves with STATVID and VICDOTSEL low, in the bank TPI2's PC6 and PC7 pick" do
      { 0xde06 => 0xa1, 0xdf05 => 0xc0 }.each { |addr, value| machine.poke(addr, value) }
      picked = [0x00, 0x40, 0x80, 0xc0].map { |lines| both_halves(lines) }
      expect(picked).to eq([[0x10, 0x10], [0x11, 0x11], [0x12, 0x12], [0x13, 0x13]])
    end

    def both_halves(lines)
      machine.poke(0xdf02, lines)
      [bank.peek(0x1234), bank.peek_phi2(0x1234)]
    end
  end

  # Twenty-five bad lines a frame, 40 cycles each and the three BA falls
  # ahead of them, which a JMP loop never writes through.
  it "halts the CPU for 1,075 cycles a PAL frame with the display on" do
    machine = looping
    machine.poke(0xd811, 0x1b)
    machine.run_cycles(19_656)
    expect(19_656 - cpu_cycles_over(machine, 19_656)).to eq(1_075)
  end

  def cpu_cycles_over(machine, cycles)
    before = machine.cpu.cycles
    machine.run_cycles(cycles)
    machine.cpu.cycles - before
  end

  it "pulls the CPU's IRQ with the VIC's raster interrupt" do
    machine = looping
    machine.poke(0xd812, 0x10)
    machine.poke(0xd81a, 0x01)
    machine.run_cycles(19_656)
    expect(machine.cpu.irq).to be(true)
  end

  describe "the control ports" do
    subject(:machine) { described_class.new }

    it "reads port 1's directions on PB0-PB3 and port 2's on PB4-PB7" do
      machine.joystick1.press(:up)
      machine.joystick2.press(:right)
      expect(machine.peek(0xdc01)).to eq(0x7e)
    end

    it "reads a pair of paddles on port 1 through the SID's pots while PA0 is high" do
      paddles = Badline::Input::Paddles.new
      paddles.move(100, 0)
      machine.control_ports.device1 = paddles
      { 0xdc02 => 0x03, 0xdc00 => 0x01 }.each { |addr, value| machine.poke(addr, value) }
      expect(machine.peek(0xda19)).to eq(paddles.pot_x)
    end

    it "reads no pots while PA0 and PA1 are low" do
      machine.control_ports.device1 = Badline::Input::Paddles.new
      { 0xdc02 => 0x03, 0xdc00 => 0x00 }.each { |addr, value| machine.poke(addr, value) }
      expect(machine.peek(0xda19)).to eq(0xff)
    end

    # PA6 is port 1's fire line and the VIC's light pen input.
    it "latches the light pen when port 1's fire button pulls PA6 low" do
      machine.joystick1.press(:fire)
      machine.run_cycles(2)
      expect(machine.vic.register_file[0x19] & 0x08).to eq(0x08)
    end

    it "reads port 1's fire button on PA6 and port 2's on PA7" do
      machine.joystick1.press(:fire)
      expect(machine.peek(0xdc00)).to eq(0xbf)
    end
  end

  describe "booted", :slow do
    include P500Boot

    it "shows BASIC 128's banner, then READY, once segments 0 and 1 are tested" do
      expect(screen_lines(booted("510"))).to eq(["*** commodore basic 128, v4.0 ***", "ready."])
    end

    it "prints 6*7" do
      machine = booted("510")
      machine.type_text("print 6*7\r")
      machine.run_cycles(500_000)
      expect(screen_lines(machine).last(3)).to eq(["print 6*7", " 42", "ready."])
    end

    it "types a key held down on the matrix" do
      machine = booted("510")
      machine.keyboard.press(:q)
      machine.run_cycles(100_000)
      machine.keyboard.release(:q)
      expect(screen_lines(machine).last).to eq("q")
    end
  end
end
