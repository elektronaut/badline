# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Chips::ACIA do
  subject(:acia) { described_class.new(clock, 886_724) }

  # The machine's side: its cycles, and the IRQ line and the cycle the
  # ACIA last asked to run at.
  let(:clock_class) do
    Struct.new(:cycles, :irq, :due) do
      def acia_changed(irq, due)
        self.irq = irq
        self.due = due
      end
    end
  end
  let(:clock) { clock_class.new(0, false, nil) }

  # 300 baud, 8N1: 10 bits of 16 x 384 crystal periods, 29,557.5 cycles.
  let(:character) { 29_557 }

  # Runs the ACIA up to cycle `target`, at each cycle it asked for.
  def run_to(target)
    while clock.due <= target
      clock.cycles = clock.due
      acia.run!(clock.cycles)
    end
    clock.cycles = target
  end

  def configure(control, command)
    acia.poke(0xfd03, control)
    acia.poke(0xfd02, command)
  end

  # A byte written at once, then the cycle the transmitter empties again.
  def emptied_after(control, command)
    configure(control, command)
    acia.poke(0xfd00, 0x55)
    run_to(clock.cycles + 1) until acia.status.anybits?(0x10)
    clock.cycles
  end

  describe "registers" do
    it "reads an empty transmitter, with DCD and DSR high, at reset" do
      expect(acia.peek(0xfd01)).to eq(0x70)
    end

    it "reads back the command and the control registers" do
      configure(0x1e, 0x0b)
      expect([acia.peek(0xfd02), acia.peek(0xfd03)]).to eq([0x0b, 0x1e])
    end

    it "repeats its registers through $FD0F" do
      acia.poke(0xfd0f, 0x42)
      expect(acia.peek(0xfd07)).to eq(0x42)
    end

    it "clears the command's low five bits on a programmed reset, and keeps the control" do
      configure(0xff, 0xff)
      acia.poke(0xfd01, 0)
      expect([acia.command, acia.control]).to eq([0xe0, 0xff])
    end

    it "clears the RES line's way: everything but the device" do
      configure(0x1e, 0x0b)
      acia.reset!
      expect([acia.command, acia.control, acia.status]).to eq([0, 0, 0x70])
    end

    it "takes the transmitter's empty flag away on a write to the data register" do
      acia.poke(0xfd00, 0x41)
      expect(acia.peek(0xfd01)).to eq(0x60)
    end

    it "drives DTR and RTS from the command register" do
      configure(0x16, 0x09)
      expect([acia.dtr?, acia.rts?, acia.break?]).to eq([true, true, false])
    end

    it "sends a break with transmitter control 11" do
      configure(0x16, 0x0d)
      expect(acia.break?).to be(true)
    end
  end

  describe "the transmitter" do
    before { acia.plug(described_class::TERMINAL) }

    it "takes a byte a character after it comes on" do
      expect(emptied_after(0x16, 0x09)).to eq(character)
    end

    it "takes the next byte at the end of the character it sends" do
      first = emptied_after(0x16, 0x09)
      acia.poke(0xfd00, 0x41)
      run_to(first + character + 1)
      expect([acia.status & 0x10, acia.drain]).to eq([0x10, [0x55]])
    end

    {
      "7 bits with even parity in 10 bits" => [0x36, 0x69, 29_557],
      "8 bits and two stop bits in 11" => [0x96, 0x09, 32_513],
      "8 bits, parity and one stop bit in 11" => [0x96, 0x29, 32_513],
      "5 bits and one and a half stop bits in 7.5" => [0xf6, 0x09, 22_168],
      "115,200 baud from the external clock" => [0x10, 0x09, 76]
    }.each do |frame, (control, command, cycles)|
      it "times a character of #{frame}" do
        expect(emptied_after(control, command)).to eq(cycles)
      end
    end

    it "sends the byte's word length" do
      configure(0x76, 0x09)
      acia.poke(0xfd00, 0xff)
      run_to(3 * character)
      expect(acia.drain).to eq([0x1f])
    end

    it "keeps a byte while it is off" do
      configure(0x16, 0x01)
      acia.poke(0xfd00, 0x55)
      run_to(3 * character)
      expect([acia.status & 0x10, acia.drain]).to eq([0, []])
    end

    it "interrupts at a character's end while empty, with its interrupt on" do
      configure(0x16, 0x07)
      run_to(character + 1)
      expect([clock.irq, acia.peek(0xfd01)]).to eq([true, 0x90])
    end

    it "clears the interrupt when the status is read" do
      configure(0x16, 0x07)
      run_to(character + 1)
      acia.peek(0xfd01)
      expect([clock.irq, acia.status]).to eq([false, 0x10])
    end

    it "interrupts again each character it stays empty" do
      configure(0x16, 0x07)
      run_to(character + 1)
      acia.peek(0xfd01)
      run_to((2 * character) + 2)
      expect(clock.irq).to be(true)
    end

    it "doesn't interrupt with its interrupt off" do
      configure(0x16, 0x0b)
      run_to(3 * character)
      expect([clock.irq, acia.status]).to eq([false, 0x10])
    end

    it "doesn't interrupt with DTR off" do
      configure(0x16, 0x04)
      run_to(3 * character)
      expect(clock.irq).to be(false)
    end
  end

  describe "the receiver" do
    before do
      acia.plug(described_class::TERMINAL)
      configure(0x16, 0x09)
    end

    it "fills its data register a character after the terminal sends" do
      acia.feed([0x41])
      run_to(character + 1)
      expect([acia.status, clock.irq, acia.peek(0xfd00)]).to eq([0x98, true, 0x41])
    end

    it "is empty again once its data is read" do
      acia.feed([0x41])
      run_to(character + 1)
      acia.peek(0xfd00)
      expect(acia.status & 0x08).to eq(0)
    end

    it "loses a byte that comes while the last is unread to an overrun" do
      acia.feed([0x41, 0x42])
      run_to((2 * character) + 2)
      expect([acia.status & 0x0c, acia.peek(0xfd00)]).to eq([0x0c, 0x41])
    end

    it "clears the overrun on a programmed reset" do
      acia.feed([0x41, 0x42])
      run_to((2 * character) + 2)
      acia.poke(0xfd01, 0)
      expect(acia.status & 0x04).to eq(0)
    end

    it "takes nothing from the terminal while DTR is off" do
      acia.poke(0xfd02, 0x08)
      acia.feed([0x41])
      run_to(3 * character)
      expect(acia.status & 0x08).to eq(0)
    end

    it "hears nothing on the RxC pin's clock" do
      acia.poke(0xfd03, 0x06)
      acia.feed([0x41])
      run_to(3 * character)
      expect(acia.status & 0x08).to eq(0)
    end

    it "doesn't interrupt with its interrupt disabled" do
      acia.poke(0xfd02, 0x0b)
      acia.feed([0x41])
      run_to(character + 1)
      expect(clock.irq).to be(false)
    end

    it "echoes what it receives in echo mode" do
      acia.poke(0xfd02, 0x13)
      acia.feed([0x41])
      run_to(character + 1)
      expect(acia.drain).to eq([0x41])
    end
  end

  describe "the user port's devices" do
    it "asserts DCD and DSR with a terminal" do
      acia.plug(described_class::TERMINAL)
      expect(acia.status).to eq(0x10)
    end

    it "interrupts as DCD and DSR change, with the receiver's interrupt on" do
      configure(0x16, 0x01)
      acia.plug(described_class::TERMINAL)
      expect([clock.irq, acia.status]).to eq([true, 0x90])
    end

    it "returns DTR to DCD and DSR with a loopback plug" do
      acia.plug(described_class::LOOPBACK)
      configure(0x16, 0x0b)
      expect(acia.status).to eq(0x10)
    end

    it "receives what it sends with a loopback plug" do
      acia.plug(described_class::LOOPBACK)
      configure(0x16, 0x09)
      acia.poke(0xfd00, 0x41)
      run_to((2 * character) + 1)
      expect(acia.peek(0xfd00)).to eq(0x41)
    end

    it "takes nothing the host feeds without a terminal" do
      configure(0x16, 0x09)
      acia.feed([0x41])
      run_to(3 * character)
      expect(acia.status & 0x08).to eq(0)
    end
  end

  describe "on the Plus/4" do
    it "pulls the CPU's IRQ line" do
      machine = Badline::Plus4.new
      machine.acia.poke(0xfd03, 0x10)
      machine.acia.poke(0xfd02, 0x05)
      machine.run_cycles(200)
      expect(machine.cpu.irq).to be(true)
    end

    it "sends what the KERNAL prints to an RS-232 file", :slow do
      machine = Badline::Plus4.new
      machine.acia.plug(described_class::TERMINAL)
      machine.on_init { machine.type_text("open2,2,0,chr$(26)+chr$(5):print#2,\"hello\";\r") }
      machine.run_cycles(500_000)
      expect(machine.acia.drain.pack("C*")).to eq("HELLO")
    end
  end
end
