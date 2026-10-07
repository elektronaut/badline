# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::PortWiring do
  subject(:machine) { Badline::Vic20.new }

  let(:bus) { machine.bus }
  let(:lines) { machine.iec_bus.host_lines }

  # The KERNAL's IOINIT ($FDF9): ATN an output on PA7 and released, the
  # clock and the data line driven low on CA2 and CB2, so released.
  def release_serial_lines
    bus.poke(0x9113, 0x80)
    bus.poke(0x911f, 0x00)
    bus.poke(0x912c, 0xcc)
  end

  context "when the VIAs come out of reset" do
    it "pulls ATN, the clock and the data line, their outputs floating high" do
      expect(lines).to eq(0x38)
    end
  end

  context "when the KERNAL lets the lines go" do
    before { release_serial_lines }

    it "pushes no line pulled" do
      expect(lines).to eq(0)
    end
  end

  context "when PA7 drives ATN" do
    before do
      release_serial_lines
      bus.poke(0x911f, 0x80)
    end

    it "pulls ATN" do
      expect(lines).to eq(Badline::IECBus::HOST_ATN_OUT)
    end
  end

  context "when CA2 drives high" do
    before do
      release_serial_lines
      bus.poke(0x912c, 0xce)
    end

    it "pulls the clock" do
      expect(lines).to eq(Badline::IECBus::HOST_CLK_OUT)
    end
  end

  context "when CB2 drives high" do
    before do
      release_serial_lines
      bus.poke(0x912c, 0xec)
    end

    it "pulls the data line" do
      expect(lines).to eq(Badline::IECBus::HOST_DATA_OUT)
    end
  end

  context "when the bus's clock is pulled" do
    before { release_serial_lines }

    it "reads it back low on VIA 1's PA0" do
      bus.poke(0x912c, 0xce)
      expect(bus.peek(0x911f) & 0x03).to eq(0x02)
    end
  end

  describe "the datasette" do
    let(:datasette) { machine.datasette }

    it "runs its motor while VIA 1's CA2 drives low" do
      bus.poke(0x911c, 0xfc)
      expect(datasette.motor?).to be(true)
    end

    it "stops its motor while VIA 1's CA2 drives high" do
      bus.poke(0x911c, 0xfe)
      expect(datasette.motor?).to be(false)
    end

    it "pulses VIA 2's CA1 on a falling edge of the read line" do
      datasette.insert(instance_double(Badline::Storage::TAP, rewind: nil, next_pulse: 1))
      datasette.play!
      bus.poke(0x911c, 0xfc)
      machine.run_cycles(2)
      expect(machine.via2.interrupt_flags & 0x02).to eq(0x02)
    end

    it "takes VIA 2's PB3 as its write line" do
      tape = instance_double(Badline::Storage::TAP, rewind: nil, record_pulse: nil)
      datasette.insert(tape)
      datasette.record!
      [[0x911c, 0xfc], [0x9122, 0xff], [0x9120, 0xf7], [0x9120, 0xff]].each { |addr, value| bus.poke(addr, value) }
      expect(tape).to have_received(:record_pulse)
    end
  end
end
