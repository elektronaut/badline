# frozen_string_literal: true

require "spec_helper"

describe Badline::C128::MMU do
  subject(:mmu) { described_class.new }

  it "powers on in C64 mode with the 8502 selected" do
    expect([mmu.mode, mmu.registers[5]]).to eq([:c64, 0x41])
  end

  it "reads its version as two banks of version 0" do
    expect(mmu.registers[11]).to eq(0x20)
  end

  it "shows the VIC bank 0" do
    expect(mmu.vic_bank).to eq(0)
  end

  it "comes back to C64 mode on a reset" do
    mmu.registers[5] = 0
    mmu.reset!
    expect(mmu.mode).to eq(:c64)
  end
end
