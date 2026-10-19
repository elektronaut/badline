# frozen_string_literal: true

require "spec_helper"
require "badline/drives/model1001"

describe Badline::Drives::Model1001 do
  subject(:drive) { described_class.new }

  it "names itself the 1001" do
    expect([drive.model_name, drive.sides]).to eq(["1001", 2])
  end

  # The first 1 KB of 251257-02A, the 2 KB EPROM, as its A10 grounded reads.
  it "runs 251257-02A in the controller's 6530 at $FC00" do
    expect((0xfc00..0xffff).map { |addr| drive.fdc_bus.peek(addr) }).to eq(Badline::ROM.read("1001/fdc-251257-02a.rom"))
  end

  it "starts the controller at $FC04 and takes its interrupt at $FF40" do
    vectors = [0xfffc, 0xfffd, 0xfffe, 0xffff].map { |addr| drive.fdc_bus.peek(addr) }
    expect(vectors).to eq([0x04, 0xfc, 0x40, 0xff])
  end

  it "takes a disk in drive 0" do
    drive.insert(nil, drive: 0)
    expect(drive.disk(0)).to be_nil
  end

  it "has no drive 1 to put a disk in" do
    expect { drive.insert(nil, drive: 1) }.to raise_error(ArgumentError, /one drive/)
  end

  it "never lights drive 1's LED, which the board leaves unwired" do
    drive.control_riot.poke(0x03, 0x38)
    drive.control_riot.poke(0x02, 0x38)
    expect(drive.leds).to eq(0x06)
  end
end
