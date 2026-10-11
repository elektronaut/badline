# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Plus4::CPUPort do
  subject(:port) { described_class.new(serial_bus:, datasette:) }

  let(:serial_bus) { Badline::Drives::SerialBus.new }
  let(:datasette) { Badline::Drives::Datasette.new(level: true) }

  it "reads the released serial lines and the idle tape line high, and P5 high" do
    expect(port.peek(0x01)).to eq(0xff)
  end

  it "reads back what an output pin drives" do
    port.poke(0x00, 0x0f)
    port.poke(0x01, 0x08)
    expect(port.peek(0x01) & 0x0f).to eq(0x08)
  end

  it "pulls the serial lines its outputs drive high" do
    port.poke(0x00, 0x0f)
    port.poke(0x01, 0x05)
    expect(serial_bus.host_lines).to eq(Badline::Drives::SerialBus::HOST_ATN_OUT |
                                         Badline::Drives::SerialBus::HOST_DATA_OUT)
  end

  it "reads the CLK and DATA lines on P6 and P7" do
    port.poke(0x00, 0x0f)
    port.poke(0x01, 0x03)
    expect(port.peek(0x01) & 0xc0).to eq(0x00)
  end

  it "runs the cassette motor while P3 is low" do
    port.poke(0x00, 0x0f)
    port.poke(0x01, 0x00)
    expect(datasette.motor?).to be(true)
  end
end
