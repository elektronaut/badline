# frozen_string_literal: true

require "spec_helper"
require "badline/chips/riot"

# The rules are the MOS 6532 datasheet's (Commodore Semiconductor Group,
# 2/81): Table 1 for the addressing, Internal Organization for the ports,
# and Edge Sense Interrupt for PA7.
describe Badline::Chips::RIOT do
  subject(:riot) { described_class.new(peripheral:) }

  let(:peripheral) { nil }

  # A peripheral pulling the given port lines low.
  def pulling(port_a: 0xff, port_b: 0xff)
    double(read_a: port_a, read_b: port_b)
  end

  def flags = riot.peek(0x05)

  # A write with A4 clear: A1 enables the PA7 interrupt, A0 picks the
  # rising edge.
  def edge_control(irq: false, rising: false)
    riot.poke(0x04 | (irq ? 0x02 : 0x00) | (rising ? 0x01 : 0x00), 0x00)
  end

  describe "the RAM" do
    it "holds 128 bytes on A6-A0" do
      riot.write_ram(0x7f, 0x5a)
      expect(riot.read_ram(0xff)).to eq(0x5a)
    end

    it "is apart from the registers" do
      riot.write_ram(0x00, 0x5a)
      expect(riot.peek(0x00)).to eq(0xff)
    end
  end

  describe "the ports" do
    it "repeats the four I/O registers while A2 is low" do
      riot.poke(0x01, 0x0f)
      riot.poke(0x03, 0xf0)
      expect([riot.peek(0x19), riot.peek(0x0b)]).to eq([0x0f, 0xf0])
    end

    it "drives the output bits and floats the inputs high" do
      riot.poke(0x01, 0x0f)
      riot.poke(0x00, 0x05)
      expect(riot.port_a_output).to eq(0xf5)
    end

    it "keeps a write to the output register of an input line for when it turns output" do
      riot.poke(0x02, 0x00)
      riot.poke(0x03, 0xff)
      expect(riot.port_b_output).to eq(0x00)
    end

    context "with a peripheral pulling every line low" do
      let(:peripheral) { pulling(port_a: 0x00, port_b: 0x00) }

      before do
        riot.poke(0x01, 0xf0)
        riot.poke(0x00, 0xa0)
        riot.poke(0x03, 0xf0)
        riot.poke(0x02, 0xa0)
      end

      it "reads port A from its pins, outputs included" do
        expect(riot.peek(0x00)).to eq(0x00)
      end

      it "reads port B's output bits from its output register" do
        expect(riot.peek(0x02)).to eq(0xa0)
      end
    end

    it "pulls PA7 low from outside through pa7=" do
      riot.pa7 = false
      expect(riot.peek(0x00)).to eq(0x7f)
    end
  end

  describe "the PA7 edge detector" do
    it "sets the flag on a falling edge after reset" do
      riot.pa7 = false
      expect(flags).to eq(0x40)
    end

    it "ignores the rising edge while it watches for falling ones" do
      riot.pa7 = false
      flags
      riot.pa7 = true
      expect(flags).to eq(0x00)
    end

    it "sets the flag on a rising edge once A0 picks it" do
      riot.pa7 = false
      edge_control(rising: true)
      riot.pa7 = true
      expect(flags).to eq(0x40)
    end

    it "clears the flag on a read of the flags" do
      riot.pa7 = false
      flags
      expect(flags).to eq(0x00)
    end

    it "sees an edge PA7 drives as an output" do
      riot.poke(0x00, 0x00)
      riot.poke(0x01, 0x80)
      expect(flags).to eq(0x40)
    end

    it "sets the flag on a change of the active edge to the level PA7 sits at" do
      edge_control(rising: true)
      expect(flags).to eq(0x40)
    end

    it "pulls IRQ while A1 enabled it" do
      edge_control(irq: true)
      riot.pa7 = false
      expect(riot.irq?).to be(true)
    end

    it "sets the flag with its interrupt disabled, leaving IRQ alone" do
      riot.pa7 = false
      expect(riot.irq?).to be(false)
    end

    it "releases IRQ on the read of the flags" do
      edge_control(irq: true)
      riot.pa7 = false
      flags
      expect(riot.irq?).to be(false)
    end
  end

  describe "#reset!" do
    before do
      riot.poke(0x01, 0xff)
      riot.poke(0x03, 0xff)
      riot.poke(0x02, 0x00)
      edge_control(irq: true, rising: true)
      riot.reset!
    end

    it "clears the I/O registers, leaving every line an input" do
      expect([riot.peek(0x01), riot.peek(0x03), riot.port_b_output]).to eq([0x00, 0x00, 0xff])
    end

    it "disables the PA7 interrupt and watches for falling edges" do
      flags
      riot.pa7 = false
      expect([flags, riot.irq?]).to eq([0x40, false])
    end
  end
end
