# frozen_string_literal: true

require "spec_helper"

describe Badline::BankedRAM::Unexpanded do
  let(:bus) { Badline::AddressBus.new }

  it "leaves $D100 to the VIC" do
    bus[0xd120] = 0x05
    expect(bus[0xd020] & 0x0f).to eq(0x05)
  end

  it "shows the VIC the machine's own RAM" do
    expect(bus.video_ram).to be(bus.ram)
  end
end
