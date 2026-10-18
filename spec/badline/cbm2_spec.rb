# frozen_string_literal: true

require "spec_helper"
require_relative "../support/taken_once"

describe Badline::CBM2 do
  # The text screen at $D000 of segment 15, 80 columns, in ASCII.
  def screen(machine)
    (0...25).map do |row|
      (0...80).map do |column|
        code = machine.bus.peek_bank(15, 0xd000 + (row * 80) + column) & 0x7f
        (code < 0x20 ? code + 0x60 : code).chr
      end.join.rstrip
    end
  end

  it "is the 610 with VICE's KERNAL at 50 Hz by default" do
    machine = described_class.new
    expect([machine.model.name, machine.kernal, machine.mains_hz]).to eq(["610", "04a", 50])
  end

  it "refuses a model, a KERNAL or a mains it doesn't know" do
    aggregate_failures do
      expect { described_class.new(model: "630") }.to raise_error(ArgumentError, /no CBM-II model/)
      expect { described_class.new(kernal: "01") }.to raise_error(ArgumentError, /no CBM-II KERNAL/)
      expect { described_class.new(mains_hz: 55) }.to raise_error(ArgumentError, /50 or 60/)
    end
  end

  it "names its model, RAM and mains for the pause menu" do
    expect(described_class.new(model: "620", mains_hz: 60).model_label).to eq("620, 256K RAM, 60 HZ")
  end

  it "fills segments 1 and 2 on a 128K board and 1 to 4 on a 256K one" do
    filled = %w[610 720].map do |model|
      described_class.new(model:).bus.segment_ram.each_with_index.filter_map { |memory, segment| segment if memory }
    end
    expect(filled).to eq([[1, 2], [1, 2, 3, 4]])
  end

  it "runs BASIC 128 of the 1983 release with 901244-03b" do
    machine = described_class.new(kernal: "03b")
    expect(machine.peek(0x8000)).to eq(Badline::ROM.read("cbm2/basic128-02b.rom").first)
  end

  it "times the 600's frames at 50 and 60 Hz and the 700's, at 2 MHz" do
    frames = [["610", 50], ["610", 60], ["710", 50]].map do |model, mains_hz|
      timing = described_class.new(model:, mains_hz:).timing
      [timing.clock_hz, timing.cycles_per_line, timing.lines_per_frame]
    end
    expect(frames).to eq([[2_000_000, 128, 313], [2_000_000, 127, 262], [2_000_000, 108, 367]])
  end

  # TPI2's PC7 is high on a 700, and PC6 on a 600 at 60 Hz.
  it "reads the board's jumpers on TPI2's PC6 and PC7" do
    jumpers = [["610", 50], ["610", 60], ["710", 50]].map do |model, mains_hz|
      described_class.new(model:, mains_hz:).peek(0xdf02) & 0xc0
    end
    expect(jumpers).to eq([0x00, 0x40, 0x80])
  end

  it "reads a key down on its row line of TPI2's port C while its column line is driven low" do
    machine = described_class.new
    machine.keyboard.press(:q)
    machine.poke(0xdf04, 0xff)
    machine.poke(0xdf01, 0xfd)
    expect(machine.peek(0xdf02) & 0x3f).to eq(0x3b)
  end

  it "maps the CIA at $DC00, the ACIA at $DD00 and the TPIs at $DE00 and $DF00" do
    machine = described_class.new
    { 0xdc02 => 0x12, 0xdd02 => 0x0b, 0xde03 => 0x34, 0xdf03 => 0x56 }.each { |addr, value| machine.poke(addr, value) }
    expect([machine.cia.peek(0xdc02), machine.acia.command, machine.tpi1.peek(3), machine.tpi2.peek(3)])
      .to eq([0x12, 0x0b, 0x34, 0x56])
  end

  it "repeats the SID's registers over its page" do
    machine = described_class.new
    machine.poke(0xdaf8, 0x0f)
    expect(machine.sid.peek(0xda18)).to eq(0x0f)
  end

  it "calls the debug register's handler with a write to $DAFF" do
    machine = described_class.new
    codes = []
    machine.install_debug_register { |code| codes << code }
    machine.poke(0xdaff, 0x00)
    expect(codes).to eq([0x00])
  end

  # A machine whose CPU loops at $0400 with interrupts off, out of the
  # KERNAL's way.
  def looping(**)
    machine = described_class.new(**)
    [0x4c, 0x00, 0x04].each_with_index { |byte, i| machine.poke(0x0400 + i, byte) }
    machine.cpu.program_counter = 0x0400
    machine
  end

  describe "the mains" do
    subject(:machine) { looping(mains_hz: 60) }

    before do
      machine.poke(0xde06, 0x01)
      machine.poke(0xde05, 0x01)
    end

    it "falls on TPI1's I0 half a period in, which latches it" do
      machine.run_cycles(16_665)
      latched = machine.tpi1.latches
      machine.run_cycles(1)
      expect([latched, machine.tpi1.latches]).to eq([0, 0x01])
    end

    it "falls again a period later" do
      machine.run_cycles(16_666)
      machine.poke(0xde02, 0x00)
      machine.run_cycles(33_332)
      expect(machine.tpi1.latches).to eq(0x01)
    end

    it "pulls the CPU's IRQ through TPI1" do
      machine.run_cycles(16_667)
      expect(machine.cpu.irq).to be(true)
    end
  end

  it "latches the CIA's interrupt on TPI1's I2" do
    machine = looping
    machine.poke(0xde06, 0x01)
    [[0xdc04, 0x02], [0xdc05, 0x00], [0xdc0d, 0x81], [0xdc0e, 0x11]].each { |addr, value| machine.poke(addr, value) }
    machine.run_cycles(10)
    expect(machine.tpi1.latches).to eq(0x04)
  end

  # do_ioinit counts loops between two of the mains' edges on TPI1's I0,
  # and the editor loads the CRTC table the jumpers pick, before the RAM
  # test.
  describe "starting" do
    def started(model, mains_hz)
      machine = described_class.new(model:, mains_hz:)
      machine.run_cycles(70_000)
      [machine.cia.peek(0xdc0e), machine.crtc.registers[0], machine.crtc.registers[9]]
    end

    it "measures 50 Hz and sets the CIA's TOD to it, and loads the 600's 50 Hz table" do
      expect(started("610", 50)).to eq([0x88, 0x7f, 7])
    end

    it "measures 60 Hz, and loads the 600's 60 Hz table" do
      expect(started("610", 60)).to eq([0x08, 0x7e, 7])
    end

    it "loads the 700's table of 14 lines a row" do
      expect(started("710", 50)).to eq([0x88, 0x6b, 13])
    end
  end

  describe "booted", :slow do
    # A 610's screen's lines once BASIC is up, and after `print 6*7`.
    def booted_once
      TakenOnce.fetch(:cbm2_booted) do
        machine = described_class.new
        machine.type_text("print 6*7\r")
        machine.run_cycles(machine.init_threshold)
        ready = screen(machine).reject(&:empty?)
        machine.run_cycles(500_000)
        [ready, screen(machine).reject(&:empty?)]
      end
    end

    it "shows BASIC 128's banner, then READY, once segments 1 and 2 are tested" do
      expect(booted_once.first).to eq(["*** commodore basic 128, v4.0 ***", "ready."])
    end

    it "prints 6*7" do
      expect(booted_once.last).to eq(["*** commodore basic 128, v4.0 ***", "ready.", "print 6*7", " 42", "ready."])
    end
  end
end
