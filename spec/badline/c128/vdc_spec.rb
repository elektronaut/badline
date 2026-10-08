# frozen_string_literal: true

require "spec_helper"

describe Badline::C128::VDC do
  subject(:vdc) { described_class.new }

  def write_register(reg, value)
    vdc.poke(0xd600, reg)
    vdc.poke(0xd601, value)
  end

  def read_register(reg)
    vdc.poke(0xd600, reg)
    vdc.peek(0xd601)
  end

  it "reads ready with the 8563's version in its status" do
    expect(vdc.peek(0xd600)).to eq(0x81)
  end

  it "reads the 8568's version in its status" do
    expect(described_class.new(model: :mos8568, ram_kb: 64).peek(0xd600)).to eq(0x82)
  end

  it "mirrors its two registers through the page" do
    vdc.poke(0xd6f0, 12)
    vdc.poke(0xd6f1, 0x34)
    expect(read_register(12)).to eq(0x34)
  end

  it "stores 37 registers" do
    write_register(36, 0x0f)
    expect(read_register(36)).to eq(0x0f)
  end

  it "reads a register past the last as $FF" do
    expect(read_register(37)).to eq(0xff)
  end

  it "stores the 8568's 38th register" do
    vdc = described_class.new(model: :mos8568, ram_kb: 64)
    vdc.poke(0xd600, 37)
    vdc.poke(0xd601, 0x03)
    expect(vdc.peek(0xd601)).to eq(0x03)
  end

  describe "its RAM, through R18, R19 and R31" do
    before do
      write_register(18, 0x12)
      write_register(19, 0x34)
      write_register(31, 0xaa)
      write_register(31, 0xbb)
    end

    it "writes at the update address" do
      expect(vdc.ram[0x1234, 2]).to eq([0xaa, 0xbb])
    end

    it "moves the update address on with each access" do
      expect([read_register(18), read_register(19)]).to eq([0x12, 0x36])
    end

    it "reads at the update address" do
      write_register(19, 0x34)
      expect([read_register(31), vdc.peek(0xd601)]).to eq([0xaa, 0xbb])
    end

    it "wraps the update address at 16K" do
      write_register(18, 0x52)
      write_register(19, 0x34)
      expect(read_register(31)).to eq(0xaa)
    end
  end

  it "has 64K when built with it" do
    expect(described_class.new(model: :mos8568, ram_kb: 64).ram.length).to eq(0x10000)
  end
end
