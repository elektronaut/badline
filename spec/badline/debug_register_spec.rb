# frozen_string_literal: true

require "spec_helper"

describe Badline::DebugRegister do
  let(:address_bus) { Badline::AddressBus.new }
  let(:writes) { [] }

  before { address_bus.install_debug_register { |value| writes << value } }

  it "captures writes to $D7FF" do
    address_bus[0xd7ff] = 0xff
    expect(writes).to eq([0xff])
  end

  it "does not forward captured writes to the SID" do
    address_bus[0xd7ff] = 0x42
    expect(address_bus.sid[0xd41f]).to eq(0xff)
  end

  it "forwards other writes on the page to the SID" do
    address_bus[0xd7f8] = 0x42
    expect(address_bus.sid[0xd418]).to eq(0x42)
  end

  it "forwards reads on the page to the SID" do
    address_bus[0xd7f8] = 0x42
    expect(address_bus[0xd7f8]).to eq(0x42)
  end

  it "survives banking changes" do
    address_bus[0x01] = 0x37
    address_bus[0xd7ff] = 0x00
    expect(writes).to eq([0x00])
  end
end
