# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::Ocean do
  include CartridgeBuilder

  let(:chips) { [0, 1, 4].map { |n| chip(bank: n, fill: 0x10 + n) } }
  let(:bus) { attached_bus(build_cartridge(5, chips, game: 0)) }

  def read_every_bank
    (0..0xff).map do |value|
      bus[0xde00] = value
      bus[0x8000]
    end
  end

  context "when the image leaves banks out" do
    it "reads through every register value" do
      expect(read_every_bank).to all(be_between(0, 0xff))
    end

    it "reads a bank the image has" do
      bus[0xde00] = 0x84
      expect(bus[0x8000]).to eq(0x14)
    end

    it "reads a bank the image leaves out as erased ROM" do
      bus[0xde00] = 0x82
      expect(bus[0x8000]).to eq(0xff)
    end

    it "shows a missing bank at ROMH as well" do
      bus[0xde00] = 0x83
      expect(bus[0xa000]).to eq(0xff)
    end

    it "ignores the bank bits above the ROM size" do
      bus[0xde00] = 0x89
      expect(bus[0x8000]).to eq(0x11)
    end
  end
end
