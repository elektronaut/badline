# frozen_string_literal: true

require "spec_helper"

describe Badline::KernalTrap::IEEELineStep do
  let(:bus_class) do
    Struct.new(:memory, :reads) do
      def peek(address)
        reads << address
        memory[address]
      end

      def poke(address, value) = memory[address] = value
    end
  end
  let(:bus) { bus_class.new({ 0xde00 => 0xa5, 0xdc0d => 0x82 }, []) }

  it "writes its value without reading the register" do
    described_class.new(address: 0xde00, keep: 0, set: 0x3f).act_on(bus)
    expect([bus.memory[0xde00], bus.reads]).to eq([0x3f, []])
  end

  it "keeps the register's bits its mask names and ORs its value in" do
    described_class.new(address: 0xde00, keep: 0xf7, set: 0x10).act_on(bus)
    expect(bus.memory[0xde00]).to eq(0xb5)
  end

  it "returns the value it writes" do
    expect(described_class.new(address: 0xde00, keep: 0xff, set: 0x08).act_on(bus)).to eq(0xad)
  end

  it "only reads with IEEE_LINE_READ" do
    step = described_class.new(address: 0xdc0d, keep: Badline::KernalTrap::IEEE_LINE_READ, set: 0)
    expect([step.act_on(bus), bus.memory[0xdc0d]]).to eq([0x82, 0x82])
  end
end
