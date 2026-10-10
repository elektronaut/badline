# frozen_string_literal: true

require "spec_helper"

# Pinned by plus256k/test.prg
describe Badline::BankedRAM::Plus256k do
  let(:computer) { Badline::Computer.new(ram_expansion: :plus256k) }
  let(:bus) { computer.address_bus }

  def select_banks(low: 0, video: 0, high: 0)
    bus[0xd100] = low | (video << 2) | (high << 6)
  end

  before do
    bus[0x00] = 0x2f
    bus[0x01] = 0x37
    4.times do |bank|
      select_banks(low: bank, high: bank)
      bus[0x0200] = 0x20 + bank
      bus[0x2000] = 0x10 + bank
    end
  end

  it "banks $1000-$FFFF on bits 6-7 of $D100" do
    select_banks(high: 2)
    expect(bus[0x2000]).to eq(0x12)
  end

  it "banks $0000-$0FFF on bits 0-1 of $D100" do
    select_banks(low: 3)
    expect(bus[0x0200]).to eq(0x23)
  end

  it "banks the low and high halves apart" do
    select_banks(low: 1, high: 2)
    expect([bus[0x0200], bus[0x2000]]).to eq([0x21, 0x12])
  end

  it "keeps the machine's own RAM as the first bank" do
    select_banks
    expect(bus.ram.peek(0x2000)).to eq(0x10)
  end

  it "shows the VIC the bank bits 2-3 select" do
    select_banks(video: 3)
    expect(bus.video_ram.peek(0x2000)).to eq(0x13)
  end

  it "points the VIC's fetches at the bank bits 2-3 select" do
    select_banks(video: 3)
    expect(bus.vic.vic_bank.peek(0x2000)).to eq(0x13)
  end

  it "points the VIC's fetches back at the first bank on reset" do
    select_banks(video: 3)
    computer.reset!
    expect(bus.vic.vic_bank.peek(0x2000)).to eq(0x10)
  end

  it "reads the register as $FF" do
    expect(bus[0xd100]).to eq(0xff)
  end

  context "when bit 4 locks the register" do
    before do
      bus[0xd100] = 0x10 | (1 << 6)
      select_banks(high: 2)
    end

    it "ignores writes" do
      expect(bus[0x2000]).to eq(0x11)
    end

    it "unlocks on reset" do
      computer.reset!
      select_banks(high: 2)
      expect(bus[0x2000]).to eq(0x12)
    end
  end

  it "selects the first banks again on reset" do
    select_banks(low: 1, video: 1, high: 1)
    computer.reset!
    expect([bus[0x0200], bus[0x2000], bus.video_ram]).to eq([0x20, 0x10, bus.ram])
  end
end
