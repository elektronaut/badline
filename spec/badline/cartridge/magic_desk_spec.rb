# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::MagicDesk do
  include CartridgeBuilder

  let(:bus) { attached_bus(build_cartridge(19, chips)) }

  def read_every_bank
    (0..0xff).map do |value|
      bus[0xde00] = value
      bus[0x8000]
    end
  end

  context "when the image leaves banks out" do
    let(:chips) { [0, 1, 4].map { |n| chip(bank: n, fill: 0x10 + n) } }

    it "reads through every register value" do
      expect(read_every_bank).to all(be_between(0, 0xff))
    end

    it "reads a bank the image has" do
      bus[0xde00] = 0x04
      expect(bus[0x8000]).to eq(0x14)
    end

    it "reads a bank the image leaves out as erased ROM" do
      bus[0xde00] = 0x02
      expect(bus[0x8000]).to eq(0xff)
    end

    it "ignores the bank bits above the ROM size" do
      bus[0xde00] = 0x09
      expect(bus[0x8000]).to eq(0x11)
    end
  end

  context "with two banks" do
    let(:chips) { [0, 1].map { |n| chip(bank: n, fill: 0x10 + n) } }

    it "decodes four banks, as the smallest board does" do
      bus[0xde00] = 0x02
      expect(bus[0x8000]).to eq(0xff)
    end
  end

  context "with more than 64 banks" do
    let(:chips) { [0, 64].map { |n| chip(bank: n, fill: n) } }

    it "takes the bank from bit 6 as well" do
      bus[0xde00] = 0x40
      expect(bus[0x8000]).to eq(0x40)
    end
  end
end
