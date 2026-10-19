# frozen_string_literal: true

require "spec_helper"
require "badline/chips/rriot"

# The rules are the MCS6530 datasheet's (Commodore Semiconductor Group, MOS
# Technology): figure 8 for the register decode, Internal Organization for
# the ports and the RAM, and Interrupt Request for PB7. The timer is the
# 6532's, specified alike (see spec/badline/chips/riot/timer_spec.rb).
describe Badline::Chips::RRIOT do
  subject(:rriot) { described_class.new(rom:, peripheral:, irq_on_pb7:) }

  let(:rom) { Array.new(1024) { |index| (index * 7) & 0xff } }
  let(:peripheral) { nil }
  let(:irq_on_pb7) { true }

  def pulling(port_a: 0xff, port_b: 0xff)
    double(read_a: port_a, read_b: port_b)
  end

  def trace(cycles)
    Array.new(cycles) do
      rriot.cycle!
      yield
    end
  end

  describe "the memories" do
    it "reads its 1 KB of ROM on A9-A0" do
      expect(rriot.read_rom(0xfffd)).to eq((0x3fd * 7) & 0xff)
    end

    it "holds 64 bytes of RAM on A5-A0" do
      rriot.write_ram(0x3f, 0x5a)
      expect(rriot.read_ram(0x7f)).to eq(0x5a)
    end
  end

  %w[fdc-901869-01.rom fdc-901885-04.rom].each do |mask|
    context "with the 8050 controller's #{mask}" do
      let(:rom) { Badline::ROM.read("8050/#{mask}") }

      it "holds the reset vector $FC04 and the IRQ vector $FF3F" do
        expect([0x3fc, 0x3fd, 0x3fe, 0x3ff].map { |addr| rriot.read_rom(addr) }).to eq([0x04, 0xfc, 0x3f, 0xff])
      end
    end
  end

  describe "the ports" do
    it "repeats the four I/O registers while A2 is low" do
      rriot.poke(0x01, 0x0f)
      rriot.poke(0x03, 0xf0)
      expect([rriot.peek(0x09), rriot.peek(0x0b)]).to eq([0x0f, 0xf0])
    end

    it "drives the output bits and floats the inputs high" do
      rriot.poke(0x03, 0x0f)
      rriot.poke(0x02, 0x05)
      expect(rriot.port_b_output).to eq(0xf5)
    end

    context "with a peripheral pulling every line low" do
      let(:peripheral) { pulling(port_a: 0x00, port_b: 0x00) }

      before do
        rriot.poke(0x01, 0xf0)
        rriot.poke(0x00, 0xa0)
        rriot.poke(0x03, 0x0f)
        rriot.poke(0x02, 0x05)
      end

      it "reads port A's output bits from its output register" do
        expect(rriot.peek(0x00)).to eq(0xa0)
      end

      it "reads port B's output bits from its output register" do
        expect(rriot.peek(0x02)).to eq(0x05)
      end
    end

    it "clears the I/O registers on reset" do
      rriot.poke(0x01, 0xff)
      rriot.poke(0x00, 0x00)
      rriot.reset!
      expect([rriot.peek(0x01), rriot.port_a_output]).to eq([0x00, 0xff])
    end
  end

  describe "idling" do
    it "runs only the timer on in fast_forward" do
      rriot.poke(0x0d, 52)
      rriot.fast_forward(213)
      expect([rriot.timer.counter, rriot.quiet_cycles]).to eq([25, 415 - 213])
    end
  end

  describe "the timer" do
    it "loads with A2 high whatever A4, A1-A0 picking the divider" do
      rriot.poke(0x05, 2)
      expect(trace(9) { rriot.timer.counter }).to eq(Array.new(7, 1) + [0, 0])
    end

    it "reads the flag alone in bit 7" do
      rriot.poke(0x04, 1)
      rriot.cycle!
      expect(rriot.peek(0x07)).to eq(0x80)
    end

    it "pulls PB7 low and IRQ while A3 enabled the interrupt" do
      rriot.poke(0x0c, 1)
      rriot.cycle!
      expect([rriot.peek(0x02), rriot.irq?]).to eq([0x7f, true])
    end

    it "leaves PB7 and IRQ alone while A3 was clear" do
      rriot.poke(0x04, 1)
      rriot.cycle!
      expect([rriot.peek(0x02), rriot.irq?]).to eq([0xff, false])
    end

    # The KIM-1 User Manual's appendix H: a read of the timer after the
    # timeout restores the divide ratio. No test program has confirmed it.
    it "puts the prescaler back on a read after the timeout" do
      rriot.poke(0x06, 1)
      70.times { rriot.cycle! }
      value = rriot.peek(0x06)
      expect(trace(64) { rriot.timer.counter }).to eq(Array.new(63, value) + [value - 1])
    end

    it "disables the interrupt on reset" do
      rriot.poke(0x0c, 1)
      rriot.reset!
      rriot.cycle!
      expect(rriot.irq?).to be(false)
    end

    context "when the mask keeps PB7 a port line" do
      let(:irq_on_pb7) { false }

      it "gives no interrupt" do
        rriot.poke(0x0c, 1)
        rriot.cycle!
        expect([rriot.peek(0x02), rriot.irq?]).to eq([0xff, false])
      end
    end
  end
end
