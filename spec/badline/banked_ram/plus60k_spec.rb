# frozen_string_literal: true

require "spec_helper"

# Pinned by plus60k/test.prg and plus60k/checkregister.prg
describe Badline::BankedRAM::Plus60k do
  let(:computer) { Badline::Computer.new(ram_expansion: :plus60k) }
  let(:bus) { computer.address_bus }

  def select_bank(bank)
    bus[0xd100] = bank << 7
  end

  before do
    bus[0x00] = 0x2f
    bus[0x01] = 0x37
    select_bank(0)
    bus[0x2000] = 0x55
    bus[0x0fff] = 0x55
    select_bank(1)
    bus[0x2000] = 0xaa
    bus[0x0fff] = 0xaa
  end

  it "banks $1000-$FFFF on bit 7 of $D100" do
    select_bank(0)
    expect(bus[0x2000]).to eq(0x55)
  end

  it "reads the selected bank" do
    expect(bus[0x2000]).to eq(0xaa)
  end

  it "leaves $0000-$0FFF unbanked" do
    select_bank(0)
    expect(bus[0x0fff]).to eq(0xaa)
  end

  it "banks the RAM under the KERNAL" do
    bus[0xe000] = 0x22
    select_bank(0)
    bus[0x01] = 0x35
    expect(bus[0xe000]).not_to eq(0x22)
  end

  it "decodes the register across $D100-$D1FF" do
    bus[0xd1ff] = 0x00
    expect(bus[0x2000]).to eq(0x55)
  end

  it "reads the register as $FF" do
    expect(bus[0xd100]).to eq(0xff)
  end

  it "leaves the VIC on the machine's own RAM" do
    expect(bus.video_ram).to be(bus.ram)
  end

  it "selects the first bank again on reset" do
    computer.reset!
    expect(bus[0x2000]).to eq(0x55)
  end

  it "hides the register when I/O is banked out" do
    bus[0x01] = 0x30
    bus[0xd100] = 0x00
    bus[0x01] = 0x37
    expect(bus[0x2000]).to eq(0xaa)
  end
end
