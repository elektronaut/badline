# frozen_string_literal: true

require "spec_helper"

describe Badline::VIA do
  subject(:via) { described_class.new(start: 0x1800, peripheral:) }

  let(:peripheral) { nil }

  def run(cycles) = cycles.times { via.cycle! }

  # What the block reads now and after each of the given number of cycles.
  def trace(cycles)
    [yield] + Array.new(cycles) do
      via.cycle!
      yield
    end
  end

  # A peripheral pulling the given port lines low.
  def pulling(port_a: 0xff, port_b: 0xff)
    double(read_a: port_a, read_b: port_b)
  end

  def sr_flag? = via.interrupt_flags.anybits?(0x04)

  it "repeats its sixteen registers across 1 KB" do
    via.poke(0x1803, 0x5a)
    expect(via.peek(0x1bf3)).to eq(0x5a)
  end

  it "is out of range past its window" do
    expect { via.peek(0x1c00) }.to raise_error(Badline::Addressable::OutOfBoundsError)
  end

  it "reads back DDRB, DDRA, the ACR and the PCR" do
    [0x1802, 0x1803, 0x180b, 0x180c].each_with_index { |addr, i| via.poke(addr, 0x11 * (i + 1)) }
    expect([0x1802, 0x1803, 0x180b, 0x180c].map { |a| via.peek(a) }).to eq([0x11, 0x22, 0x33, 0x44])
  end

  describe "#reset!" do
    before do
      [[0x1800, 0xff], [0x1802, 0xff], [0x180c, 0xee], [0x180e, 0xff],
       [0x1804, 0x34], [0x1805, 0x12], [0x180a, 0xa5]].each { |addr, value| via.poke(addr, value) }
      via.ca1 = false
      via.reset!
    end

    it "clears the port, direction and control registers" do
      expect([0x1802, 0x1803, 0x180b, 0x180c].map { |a| via.peek(a) }).to eq([0, 0, 0, 0])
    end

    it "clears the flags and enables and releases IRQ" do
      expect([via.interrupt_flags, via.interrupt_enable, via.irq?]).to eq([0x00, 0x80, false])
    end

    it "floats both ports high" do
      expect([via.port_a_output, via.port_b_output]).to eq([0xff, 0xff])
    end

    it "leaves the timer latch and counter alone" do
      expect([via.timer1_latch, via.timer1]).to eq([0x1234, 0x1234])
    end

    it "leaves the shift register alone" do
      expect(via.peek(0x180a)).to eq(0xa5)
    end
  end

  describe "the ports" do
    it "drives output bits from ORA and floats inputs high" do
      via.poke(0x1803, 0x0f)
      via.poke(0x1801, 0x05)
      expect(via.port_a_output).to eq(0xf5)
    end

    it "drives output bits from ORB and floats inputs high" do
      via.poke(0x1802, 0xf0)
      via.poke(0x1800, 0x50)
      expect(via.port_b_output).to eq(0x5f)
    end

    it "writes ORA through $F as through $1" do
      via.poke(0x1803, 0xff)
      via.poke(0x180f, 0x3c)
      expect(via.port_a_output).to eq(0x3c)
    end

    it "floats the inputs high without a peripheral" do
      expect([via.peek(0x1800), via.peek(0x1801)]).to eq([0xff, 0xff])
    end

    context "with a peripheral" do
      let(:peripheral) { pulling(port_a: 0x7e, port_b: 0xbd) }

      it "reads port A's pins, output bits included" do
        via.poke(0x1803, 0xff)
        via.poke(0x1801, 0xff)
        expect(via.peek(0x1801)).to eq(0x7e)
      end

      it "reads port B's output bits from ORB and its inputs from the pins" do
        via.poke(0x1802, 0x0f)
        via.poke(0x1800, 0x0f)
        expect(via.peek(0x1800)).to eq(0xbf)
      end

      it "hands the peripheral the lines as driven" do
        via.poke(0x1803, 0x01)
        via.peek(0x1801)
        expect(peripheral).to have_received(:read_a).with(0xfe)
      end
    end
  end

  describe "input latching" do
    let(:peripheral) { pulling(port_a: 0x12, port_b: 0x34) }

    it "reads port A live while ACR bit 0 is clear" do
      via.ca1 = false
      allow(peripheral).to receive(:read_a).and_return(0x56)
      expect(via.peek(0x1801)).to eq(0x56)
    end

    it "latches port A on CA1's active edge while ACR bit 0 is set" do
      via.poke(0x180b, 0x01)
      via.ca1 = false
      allow(peripheral).to receive(:read_a).and_return(0x56)
      expect(via.peek(0x180f)).to eq(0x12)
    end

    it "ignores CA1's inactive edge" do
      via.poke(0x180c, 0x01) # CA1 active on the rising edge
      via.poke(0x180b, 0x01)
      via.ca1 = false
      expect(via.peek(0x180f)).to eq(0xff)
    end

    context "with port B latched and its low nibble output" do
      before do
        via.poke(0x180b, 0x02)
        via.poke(0x1802, 0x0f)
        via.poke(0x1800, 0x0a)
      end

      it "latches the inputs on CB1's active edge, and reads outputs from ORB" do
        via.cb1 = false
        allow(peripheral).to receive(:read_b).and_return(0xff)
        expect(via.peek(0x1800)).to eq(0x3a)
      end
    end
  end

  describe "CA1 and CB1" do
    it "flag a falling edge by default" do
      via.ca1 = false
      via.cb1 = false
      expect(via.interrupt_flags).to eq(0x12)
    end

    it "flag nothing when the level holds" do
      via.ca1 = true
      expect(via.interrupt_flags).to eq(0x00)
    end

    context "with PCR bits 0 and 4 set" do
      before do
        via.poke(0x180c, 0x11)
        via.ca1 = false
        via.cb1 = false
      end

      it "ignore the falling edge" do
        expect(via.interrupt_flags).to eq(0x00)
      end

      it "flag the rising edge" do
        via.ca1 = true
        via.cb1 = true
        expect(via.interrupt_flags).to eq(0x12)
      end
    end
  end

  describe "CA2 and CB2 as inputs" do
    def c2_edges(rising:)
      via.ca2 = via.cb2 = false
      via.ca2 = via.cb2 = true if rising
    end

    {
      "000 (falling edge)" => [0x00, false],
      "001 (independent, falling edge)" => [0x22, false],
      "010 (rising edge)" => [0x44, true],
      "011 (independent, rising edge)" => [0x66, true]
    }.each do |mode, (pcr, rising)|
      it "flag the active edge in mode #{mode}" do
        via.poke(0x180c, pcr)
        c2_edges(rising:)
        expect(via.interrupt_flags).to eq(0x09)
      end
    end

    it "flag nothing on the other edge" do
      via.poke(0x180c, 0x44)
      c2_edges(rising: false)
      expect(via.interrupt_flags).to eq(0x00)
    end

    it "flag nothing in an output mode" do
      via.poke(0x180c, 0x88)
      c2_edges(rising: false)
      expect(via.interrupt_flags).to eq(0x00)
    end

    it "read high as outputs" do
      expect([via.ca2_output, via.cb2_output]).to eq([true, true])
    end
  end

  describe "port accesses and the handshake flags" do
    before do
      via.ca1 = via.ca2 = via.cb1 = via.cb2 = false
    end

    it "clear CA1 and CA2 on a read of ORA at $1" do
      via.peek(0x1801)
      expect(via.interrupt_flags).to eq(0x18)
    end

    it "clear CA1 and CA2 on a write of ORA at $1" do
      via.poke(0x1801, 0)
      expect(via.interrupt_flags).to eq(0x18)
    end

    it "leave the flags alone through $F" do
      via.peek(0x180f)
      via.poke(0x180f, 0)
      expect(via.interrupt_flags).to eq(0x1b)
    end

    it "clear CB1 and CB2 on a read of ORB" do
      via.peek(0x1800)
      expect(via.interrupt_flags).to eq(0x03)
    end

    it "clear CB1 and CB2 on a write of ORB" do
      via.poke(0x1800, 0)
      expect(via.interrupt_flags).to eq(0x03)
    end

    it "keep an independent CA2 or CB2 flag" do
      via.poke(0x180c, 0x22)
      via.peek(0x1801)
      via.peek(0x1800)
      expect(via.interrupt_flags).to eq(0x09)
    end
  end

  describe "CA2 in handshake mode" do
    let(:peripheral) { pulling }

    before { via.poke(0x180c, 0x08) }

    it "goes low on a read of ORA and stays low" do
      via.peek(0x1801)
      run(3)
      expect(via.ca2_output).to be(false)
    end

    it "goes low on a write of ORA" do
      via.poke(0x1801, 0)
      expect(via.ca2_output).to be(false)
    end

    it "goes back high on CA1's active edge" do
      via.peek(0x1801)
      via.ca1 = false
      expect(via.ca2_output).to be(true)
    end

    it "stays high through $F" do
      via.peek(0x180f)
      via.poke(0x180f, 0)
      expect(via.ca2_output).to be(true)
    end
  end

  describe "CA2 in its other output modes" do
    let(:peripheral) { pulling }

    it "pulses low for the cycle after an access of ORA in mode 101" do
      via.poke(0x180c, 0x0a)
      via.peek(0x1801)
      expect(trace(3) { via.ca2_output }).to eq([false, false, true, true])
    end

    it "holds low in mode 110 and high in mode 111" do
      via.poke(0x180c, 0x0c)
      low = via.ca2_output
      via.poke(0x180c, 0x0e)
      expect([low, via.ca2_output]).to eq([false, true])
    end
  end

  describe "CB2 in handshake mode" do
    before { via.poke(0x180c, 0x80) }

    it "goes low on a write of ORB" do
      via.poke(0x1800, 0)
      expect(via.cb2_output).to be(false)
    end

    it "goes back high on CB1's active edge" do
      via.poke(0x1800, 0)
      via.cb1 = false
      expect(via.cb2_output).to be(true)
    end

    it "stays high on a read of ORB" do
      via.peek(0x1800)
      expect(via.cb2_output).to be(true)
    end
  end

  describe "CB2 in its other output modes" do
    it "pulses low for the cycle after a write of ORB in mode 101" do
      via.poke(0x180c, 0xa0)
      via.poke(0x1800, 0)
      expect(trace(2) { via.cb2_output }).to eq([false, false, true])
    end

    it "holds low in mode 110 and high in mode 111" do
      via.poke(0x180c, 0xc0)
      low = via.cb2_output
      via.poke(0x180c, 0xe0)
      expect([low, via.cb2_output]).to eq([false, true])
    end
  end

  describe "the interrupt registers" do
    it "read IER with bit 7 set" do
      via.poke(0x180e, 0x82)
      expect(via.peek(0x180e)).to eq(0x82)
    end

    it "set enable bits with bit 7 set and clear them with it clear" do
      via.poke(0x180e, 0xff)
      via.poke(0x180e, 0x0f)
      expect(via.peek(0x180e)).to eq(0xf0)
    end

    it "leave IRQ high while a flag is disabled" do
      via.ca1 = false
      expect([via.irq?, via.peek(0x180d)]).to eq([false, 0x02])
    end

    it "pull IRQ low and read IFR bit 7 while a flag is enabled" do
      via.poke(0x180e, 0x82)
      via.ca1 = false
      expect([via.irq?, via.peek(0x180d)]).to eq([true, 0x82])
    end

    it "pull IRQ low when a pending flag is enabled" do
      via.ca1 = false
      via.poke(0x180e, 0x82)
      expect(via.irq?).to be(true)
    end

    it "pull IRQ low on timer 1's timeout at cycle N + 2" do
      via.poke(0x180e, 0xc0)
      via.poke(0x1804, 3)
      via.poke(0x1805, 0)
      expect(trace(5) { via.irq? }).to eq(Array.new(5, false) + [true])
    end

    context "with CA1 and CB1 flagged and enabled" do
      before do
        via.poke(0x180e, 0x92)
        via.ca1 = via.cb1 = false
      end

      it "clear only the flags written as 1s, holding IRQ" do
        via.poke(0x180d, 0x02)
        expect([via.peek(0x180d), via.irq?]).to eq([0x90, true])
      end

      it "release IRQ once every enabled flag is clear" do
        via.poke(0x180d, 0x92)
        expect([via.peek(0x180d), via.irq?]).to eq([0x00, false])
      end
    end
  end

  describe "the shift register" do
    it "reads back what was written" do
      via.poke(0x180a, 0x96)
      expect(via.peek(0x180a)).to eq(0x96)
    end

    it "takes its mode from ACR bits 4-2" do
      via.poke(0x180b, 0x18)
      expect(via.shift_register.mode).to eq(6)
    end

    it "leaves CB1 undriven when disabled" do
      expect(via.cb1_output).to be_nil
    end

    context "when shifting out under φ2" do
      before do
        via.poke(0x180b, 0x18)
        via.poke(0x180a, 0x80)
      end

      it "sets its flag after eight bits, on cycle 17" do
        expect(trace(17) { sr_flag? }).to eq(Array.new(17, false) + [true])
      end

      it "clears its flag on a read of $A" do
        run(17)
        via.peek(0x180a)
        expect(sr_flag?).to be(false)
      end

      it "clears its flag on a write of $A" do
        run(17)
        via.poke(0x180a, 0x55)
        expect(sr_flag?).to be(false)
      end

      it "drives CB1 as its clock" do
        run(2)
        expect(via.cb1_output).to be(false)
      end

      it "takes CB2 over from the PCR" do
        via.poke(0x180c, 0xc0) # CB2 held low
        via.cycle!
        expect(via.cb2_output).to be(true)
      end
    end

    context "when shifting out under timer 2" do
      before do
        via.poke(0x180b, 0x14)
        via.poke(0x1808, 0x00)
        via.poke(0x1809, 0x00)
        via.poke(0x180a, 0x55)
      end

      # The load holds a cycle, then the low byte underflows every N + 2 = 2
      # cycles: the sixteenth underflow lands on cycle 32, and the eighth
      # bit's rising edge two cycles later.
      it "clocks a bit every 2 × (N + 2) cycles" do
        expect(trace(34) { sr_flag? }).to eq(Array.new(34, false) + [true])
      end
    end

    context "when shifting in under an external clock" do
      before do
        via.poke(0x180b, 0x0c)
        via.peek(0x180a)
        via.cb2 = false
      end

      def clock_cb1(count)
        count.times do
          via.cb1 = false
          via.cb1 = true
        end
      end

      it "shifts CB2 in on CB1 edges and sets its flag after eight" do
        clock_cb1(8)
        expect([via.peek(0x180d) & 0x04, via.peek(0x180a)]).to eq([0x04, 0x00])
      end
    end
  end
end
