# frozen_string_literal: true

require "spec_helper"

describe Badline::Chips::PIA do
  subject(:pia) { described_class.new(peripheral:) }

  let(:peripheral) { nil }

  # A peripheral pulling the given port lines low.
  def pulling(port_a: 0xff, port_b: 0xff)
    double(read_a: port_a, read_b: port_b)
  end

  # Selects both ports, with the rest of each control register as given.
  def select_ports(cra: 0x00, crb: 0x00)
    pia.poke(0x01, cra | 0x04)
    pia.poke(0x03, crb | 0x04)
  end

  def trace(cycles)
    [yield] + Array.new(cycles) do
      pia.cycle!
      yield
    end
  end

  it "repeats its four registers on two address lines" do
    pia.poke(0x00, 0x5a)
    expect(pia.peek(0xe80c)).to eq(0x5a)
  end

  it "reads the direction registers while bit 2 is clear" do
    pia.poke(0x00, 0x0f)
    pia.poke(0x02, 0xf0)
    expect([pia.peek(0x00), pia.peek(0x02)]).to eq([0x0f, 0xf0])
  end

  it "writes the port, not the direction register, while bit 2 is set" do
    select_ports
    pia.poke(0x00, 0x55)
    expect([pia.port_a_output, pia.peek(0x00)]).to eq([0xff, 0xff])
  end

  it "reads back bits 0-5 of each control register" do
    pia.poke(0x01, 0xff)
    pia.poke(0x03, 0x2a)
    expect([pia.cra, pia.peek(0x03)]).to eq([0x3f, 0x2a])
  end

  describe "#reset!" do
    before do
      pia.poke(0x00, 0xff)
      select_ports(cra: 0x03, crb: 0x03)
      pia.ca1 = false
      pia.ca1 = true
      pia.reset!
    end

    it "clears the direction and control registers" do
      expect([pia.peek(0x00), pia.peek(0x01), pia.peek(0x02), pia.peek(0x03)]).to eq([0, 0, 0, 0])
    end

    it "releases IRQ and floats every line high" do
      expect([pia.irq?, pia.port_a_output, pia.port_b_output, pia.ca2_output, pia.cb2_output])
        .to eq([false, 0xff, 0xff, true, true])
    end
  end

  describe "the ports" do
    it "drives output bits from the output register and floats inputs high" do
      pia.poke(0x00, 0x0f)
      select_ports
      pia.poke(0x00, 0x05)
      expect(pia.port_a_output).to eq(0xf5)
    end

    context "with a peripheral pulling lines low" do
      let(:peripheral) { pulling(port_a: 0x7e, port_b: 0x7e) }

      before do
        pia.poke(0x00, 0x81)
        pia.poke(0x02, 0x81)
        select_ports
        pia.poke(0x00, 0xff)
        pia.poke(0x02, 0xff)
      end

      it "reads port A from its pins, outputs included" do
        expect(pia.peek(0x00)).to eq(0x7e)
      end

      it "reads port B's outputs from its output register and its inputs from the pins" do
        expect(pia.peek(0x02)).to eq(0xff)
      end
    end

    context "with a peripheral listening" do
      let(:peripheral) { pulling }

      it "hands it the lines the port drives" do
        pia.poke(0x02, 0x0f)
        select_ports
        pia.poke(0x02, 0x03)
        pia.peek(0x02)
        expect(peripheral).to have_received(:read_b).with(0xf3)
      end
    end
  end

  describe "C1" do
    it "sets the flag on a falling edge by default" do
      pia.ca1 = false
      expect(pia.cra).to eq(0x80)
    end

    it "ignores the other edge" do
      pia.poke(0x01, 0x02)
      pia.ca1 = false
      expect(pia.cra & 0x80).to eq(0)
    end

    it "sets the flag on a rising edge when bit 1 is set" do
      pia.poke(0x03, 0x02)
      pia.cb1 = false
      pia.cb1 = true
      expect(pia.crb).to eq(0x82)
    end

    it "sets the flag with its interrupt off, without pulling IRQ" do
      pia.cb1 = false
      expect([pia.crb, pia.irq?]).to eq([0x80, false])
    end

    it "pulls IRQB once enabled, and not IRQA" do
      pia.poke(0x03, 0x01)
      pia.cb1 = false
      expect([pia.irqb?, pia.irqa?, pia.irq?]).to eq([true, false, true])
    end

    it "pulls IRQ when its interrupt is enabled after the flag is set" do
      pia.ca1 = false
      pia.poke(0x01, 0x01)
      expect(pia.irqa?).to be(true)
    end

    it "keeps its flag through a write of the control register" do
      pia.ca1 = false
      pia.poke(0x01, 0x05)
      expect(pia.cra).to eq(0x85)
    end
  end

  describe "the flags" do
    before do
      select_ports(cra: 0x01, crb: 0x01)
      pia.ca1 = false
      pia.ca2 = false
      pia.cb1 = false
    end

    it "are both cleared by a read of the port, which releases IRQ" do
      pia.peek(0x00)
      expect([pia.cra, pia.irqa?]).to eq([0x05, false])
    end

    it "are not cleared by a read of the direction register" do
      pia.poke(0x01, 0x01)
      pia.peek(0x00)
      expect(pia.cra).to eq(0xc1)
    end

    it "are not cleared by a write of the port" do
      pia.poke(0x02, 0x00)
      expect(pia.crb).to eq(0x85)
    end

    it "clear on one side only" do
      pia.peek(0x02)
      expect([pia.cra, pia.crb]).to eq([0xc5, 0x05])
    end
  end

  describe "C2 as an input" do
    it "sets the flag on a falling edge, without IRQ while bit 3 is clear" do
      pia.cb2 = false
      expect([pia.crb, pia.irq?]).to eq([0x40, false])
    end

    it "sets the flag on a rising edge when bit 4 is set" do
      pia.poke(0x01, 0x10)
      pia.ca2 = false
      pia.ca2 = true
      expect(pia.cra).to eq(0x50)
    end

    it "pulls IRQ while bit 3 is set" do
      pia.poke(0x01, 0x08)
      pia.ca2 = false
      expect(pia.irqa?).to be(true)
    end

    it "loses its flag when C2 becomes an output" do
      pia.ca2 = false
      pia.poke(0x01, 0x38)
      expect(pia.cra).to eq(0x38)
    end

    it "sets no flag while C2 is an output" do
      pia.poke(0x03, 0x38)
      pia.cb2 = false
      expect(pia.crb).to eq(0x38)
    end
  end

  describe "C2 as an output" do
    it "drives bit 3 in manual mode" do
      pia.poke(0x01, 0x30)
      pia.poke(0x03, 0x38)
      expect([pia.ca2_output, pia.cb2_output]).to eq([false, true])
    end

    context "with CA2 in handshake mode" do
      before do
        select_ports(cra: 0x20)
        pia.peek(0x00)
      end

      it "goes low on a read of port A" do
        expect(pia.ca2_output).to be(false)
      end

      it "stays low until the active CA1 edge" do
        stayed = trace(3) { pia.ca2_output }
        pia.ca1 = false
        expect(stayed + [pia.ca2_output]).to eq([false, false, false, false, true])
      end
    end

    it "doesn't strobe CA2 on a write of port A" do
      select_ports(cra: 0x20)
      pia.poke(0x00, 0x00)
      expect(pia.ca2_output).to be(true)
    end

    it "pulses CA2 low for the cycle after a read of port A" do
      select_ports(cra: 0x28)
      pia.peek(0x00)
      expect(trace(2) { pia.ca2_output }).to eq([false, false, true])
    end

    it "strobes CB2 on a write of port B, not a read" do
      select_ports(crb: 0x20)
      pia.peek(0x02)
      read = pia.cb2_output
      pia.poke(0x02, 0x00)
      expect([read, pia.cb2_output]).to eq([true, false])
    end

    it "pulses CB2 low for the cycle after a write of port B" do
      select_ports(crb: 0x28)
      pia.poke(0x02, 0x00)
      expect(trace(2) { pia.cb2_output }).to eq([false, false, true])
    end

    it "releases a handshake when the mode changes" do
      select_ports(cra: 0x20)
      pia.peek(0x00)
      pia.poke(0x01, 0x2c)
      pia.poke(0x01, 0x24)
      expect(pia.ca2_output).to be(true)
    end

    it "doesn't strobe through the direction register" do
      pia.poke(0x03, 0x20)
      pia.poke(0x02, 0xff)
      expect(pia.cb2_output).to be(true)
    end
  end
end
