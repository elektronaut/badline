# frozen_string_literal: true

require "spec_helper"
require "badline/chips/tpi"

# The rules are the MPS 6525 datasheet's (Commodore Semiconductor Group):
# "6525 Internal Registers" and "Port Registers" on page 2-81, "CA and CB
# Outputs", "I4, I3, I2, I1, I0 Inputs", "Interrupt Mask Register" and
# "Description of Priority Interrupt Operation" on 2-82, and its examples
# A to C and "Initialization" on 2-82 and 2-83.
describe Badline::Chips::TPI do
  subject(:tpi) { described_class.new(peripheral:) }

  let(:peripheral) { nil }

  # Mode 1 (MC), with priority (IP) unless told otherwise, every interrupt
  # unmasked, and +control+'s other bits.
  def mode1(priority: true, control: 0x00)
    tpi.poke(6, control | 0x01 | (priority ? 0x02 : 0x00))
    tpi.poke(5, 0x1f)
  end

  # A falling edge on input +index+.
  def fall(index)
    tpi.interrupt_line(index, false)
    tpi.interrupt_line(index, true)
  end

  def air = tpi.peek(7)

  describe "the registers" do
    it "repeats them every 8 bytes" do
      tpi.poke(0x0b, 0x5a)
      expect(tpi.peek(0x03)).to eq(0x5a)
    end

    it "reads a port's outputs from its register and its inputs floating high" do
      tpi.poke(0, 0x0f)
      tpi.poke(3, 0x3c)
      expect(tpi.peek(0)).to eq(0xcf)
    end

    context "with a peripheral pulling lines low" do
      let(:peripheral) { double(read_a: 0xff, read_b: 0xff, read_c: 0xf0) }

      it "reads port C's input pins from it in mode 0" do
        expect(tpi.peek(2)).to eq(0xf0)
      end
    end

    it "clears every register on RES, back to mode 0 with every pin an input" do
      mode1
      tpi.poke(0, 0x12)
      tpi.reset!
      expect((0..6).map { |register| tpi.peek(register) }).to eq([0xff, 0xff, 0xff, 0, 0, 0, 0])
    end
  end

  # The register table on page 2-81 has DDRC's bits 0-4 as the mask in
  # mode 1: DDRC keeps all eight bits written.
  it "reads back DDRC's eight bits in mode 1, its low five the mask" do
    mode1
    tpi.poke(5, 0xe1)
    expect([tpi.peek(5), tpi.mask]).to eq([0xe1, 0x01])
  end

  describe "the interrupt inputs" do
    it "latch on a falling edge of I0-I2 in mode 1" do
      mode1
      [0, 1, 2].each { |index| fall(index) }
      expect(tpi.peek(2) & 0x1f).to eq(0x07)
    end

    it "latch nothing in mode 0" do
      fall(0)
      tpi.poke(6, 0x01)
      expect(tpi.peek(2) & 0x1f).to eq(0)
    end

    it "latch I3 and I4 on the rising edge IE3 and IE4 select" do
      mode1(control: 0x0c)
      tpi.interrupt_line(3, false)
      tpi.interrupt_line(4, false)
      expect(tpi.latches).to eq(0)
    end

    it "latch I3 on its rising edge with IE3 set" do
      mode1(control: 0x04)
      fall(3)
      expect(tpi.latches).to eq(0x08)
    end

    it "latch whether or not the mask enables them, and only the unmasked interrupt" do
      mode1
      tpi.poke(5, 0x00)
      fall(1)
      expect([tpi.latches, tpi.irq?]).to eq([0x02, false])
    end

    it "clear a latch on a write of 0 to its bit of PRC, and not on a 1" do
      mode1
      fall(0)
      fall(1)
      tpi.poke(2, 0xfe)
      expect(tpi.latches).to eq(0x02)
    end

    it "read IRQ low in PC5 while it is active" do
      mode1
      fall(0)
      expect(tpi.peek(2) & 0x20).to eq(0)
    end
  end

  describe "without priority" do
    before { mode1(priority: false) }

    it "shows every unmasked latch in the AIR" do
      fall(0)
      fall(2)
      expect(tpi.peek(7)).to eq(0x05)
    end

    it "clears the AIR, its latches and IRQ on a read of it" do
      fall(0)
      fall(2)
      tpi.peek(7)
      expect([tpi.latches, tpi.irq?]).to eq([0, false])
    end
  end

  # Example A, single interrupt.
  describe "a single interrupt with priority" do
    before do
      mode1
      fall(1)
    end

    it "sets A1 and pulls IRQ low" do
      expect([tpi.irq?, tpi.peek(2) & 0x1f]).to eq([true, 0x02])
    end

    it "pushes the AIR and clears it, latch 1 and IRQ on a read" do
      expect([air, tpi.stack, tpi.latches, tpi.irq?]).to eq([0x02, [0x02], 0, false])
    end

    it "pops the stack on a write of the AIR" do
      air
      tpi.poke(7, 0)
      expect(tpi.stack).to eq([])
    end
  end

  # Example B, a lower priority interrupt during an active one.
  describe "a lower interrupt while one is in service" do
    before do
      mode1
      fall(1)
      air
      fall(0)
    end

    it "keeps I0 from interrupting until I1's service ends" do
      expect([tpi.irq?, tpi.latches]).to eq([false, 0x01])
    end

    it "lets I0 interrupt once the AIR is written" do
      tpi.poke(7, 0)
      expect([tpi.irq?, air]).to eq([true, 0x01])
    end
  end

  # Example C, a higher priority interrupt during an active one.
  describe "a higher interrupt while one is in service" do
    before do
      mode1
      fall(1)
      air
      fall(2)
    end

    it "sets A2 and pulls IRQ low" do
      expect([tpi.irq?, air]).to eq([true, 0x04])
    end

    it "restores I1's status to the top of the stack when I2's service ends, still holding I0 off" do
      air
      tpi.poke(7, 0)
      fall(0)
      expect([tpi.stack, tpi.irq?]).to eq([[0x02], false])
    end

    it "leaves no interrupt active once I1's service ends too" do
      air
      tpi.poke(7, 0)
      tpi.poke(7, 0)
      expect([tpi.stack, tpi.irq?]).to eq([[], false])
    end
  end

  it "ranks I4 over I3 over I2 over I1 over I0" do
    mode1
    [0, 1, 2, 3, 4].each { |index| fall(index) }
    expect(air).to eq(0x10)
  end

  it "keeps five levels on the stack" do
    mode1
    6.times { air }
    expect(tpi.stack.length).to eq(5)
  end

  describe "CA and CB" do
    it "set CA high on I3's active edge and low on a read of PRA in mode 00" do
      mode1
      fall(3)
      high = tpi.ca?
      tpi.peek(0)
      expect([high, tpi.ca?]).to eq([true, false])
    end

    it "set CB low on a write of PRB and high on I4's active edge in mode 00" do
      mode1
      fall(4)
      high = tpi.cb?
      tpi.poke(1, 0)
      expect([high, tpi.cb?]).to eq([true, false])
    end

    it "hold CA and CB at the level modes 10 and 11 give them" do
      mode1(control: 0xb0)
      expect([tpi.ca?, tpi.cb?, tpi.peek(2) & 0xc0]).to eq([true, false, 0x40])
    end
  end
end
