# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::CPU do
  subject(:cpu) { described_class.new(bus) }

  let(:bus) do
    Badline::Vic20::Bus.new(vic: Badline::Memory.new([], length: 0x100, start: 0x9000),
                            via1: Badline::VIA.new(start: 0x9000), via2: Badline::VIA.new(start: 0x9000))
  end

  it "starts at the KERNAL's reset vector" do
    expect(cpu.program_counter).to eq(0xfd22)
  end

  it "runs from RAM" do
    bus.ram.write(0x1000, [0xa9, 0x42, 0x8d, 0x00, 0x02]) # LDA #$42; STA $0200
    cpu.program_counter = 0x1000
    2.times { cpu.step! }
    expect(bus.peek(0x0200)).to eq(0x42)
  end

  it "reads the high byte of LDA abs's address from an empty block" do
    bus.ram.write(0x1000, [0xad, 0x34, 0x72]) # LDA $7234
    cpu.program_counter = 0x1000
    cpu.step!
    expect(cpu.a).to eq(0x72)
  end
end
