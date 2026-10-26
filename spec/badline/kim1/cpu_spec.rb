# frozen_string_literal: true

require "spec_helper"

describe Badline::KIM1::CPU do
  subject(:kim) { Badline::KIM1.new }

  let(:cpu) { kim.cpu }

  # LDA #$01, TAX and INX at $0200, with the CPU about to fetch the LDA.
  before do
    [0xa9, 0x01, 0xaa, 0xe8].each_with_index { |byte, offset| kim.poke(0x0200 + offset, byte) }
    cpu.program_counter = 0x0200
    cpu.stack_pointer = 0xff
  end

  # The cycles until the CPU fetches from the NMI vector's JMP at $1C1C.
  def cycles_to_nmi
    count = 0
    until cpu.program_counter == 0x1c1c && cpu.boundary?
      kim.cycle!
      count += 1
    end
    count
  end

  def pushed_pc = kim.peek(0x01fe) | (kim.peek(0x01ff) << 8)

  # Pinned by the KIM-1 User Manual's figure 5.6, which single-steps the
  # 2-cycle LDA #$01 and TAX one at a time.
  it "takes the NMI single-step pulls right after a 2-cycle instruction" do
    kim.sst = true
    expect([cycles_to_nmi, pushed_pc]).to eq([2 + 7, 0x0202])
  end

  it "steps the next instruction once the monitor returns to it" do
    kim.sst = true
    cycles_to_nmi
    cpu.stack_pointer = 0xff
    cpu.program_counter = 0x0202
    expect([cycles_to_nmi, pushed_pc]).to eq([2 + 7, 0x0203])
  end

  it "leaves the monitor's fetches in K7 alone" do
    kim.sst = true
    cpu.program_counter = 0xfc22
    kim.run_cycles(500)
    expect([cpu.nmi, cpu.program_counter & 0x1c00]).to eq([false, 0x1c00])
  end

  it "pulls nothing with SST off" do
    kim.run_cycles(6)
    expect([cpu.program_counter, cpu.x]).to eq([0x0204, 0x02])
  end
end
