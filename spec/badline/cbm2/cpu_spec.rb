# frozen_string_literal: true

require "spec_helper"
require "badline/cbm2"

describe Badline::CBM2::CPU do
  subject(:cpu) { described_class.new(bus) }

  let(:bus) { Badline::CBM2::Bus.new(basic: "cbm2/basic128.rom", kernal: "cbm2/kernal-04a.rom", ram_segments: [0, 1, 2]) }

  # Puts +code+ at $0400 of segment 15 and runs it to the BRK at its end,
  # with the pointer at $FE in segment 15 pointing to $0634.
  def run(code, indirect: 2)
    bus.poke(0x0001, indirect)
    bus.poke(0x00fe, 0x34)
    bus.poke(0x00ff, 0x06)
    code.each_with_index { |byte, i| bus.poke(0x0400 + i, byte) }
    cpu.program_counter = 0x0400
    cpu.step! until bus.peek(cpu.program_counter).zero?
  end

  it "reads LDA (zp),Y's data from the indirection segment" do
    bus.poke_bank(2, 0x0635, 0x5a)
    run([0xa0, 0x01, 0xb1, 0xfe]) # LDY #1, LDA ($FE),Y
    expect(cpu.a).to eq(0x5a)
  end

  it "writes STA (zp),Y's data to the indirection segment" do
    run([0xa9, 0x99, 0xa0, 0x00, 0x91, 0xfe]) # LDA #$99, LDY #0, STA ($FE),Y
    expect([bus.peek_bank(2, 0x0634), bus.peek_bank(15, 0x0634)]).to eq([0x99, 0x00])
  end

  it "reads the pointer from the execution segment" do
    bus.poke_bank(2, 0x00fe, 0x00)
    bus.poke_bank(2, 0x0634, 0x77)
    run([0xa0, 0x00, 0xb1, 0xfe])
    expect(cpu.a).to eq(0x77)
  end

  it "takes the indirection segment across a page boundary" do
    bus.poke_bank(2, 0x0700, 0x3c)
    run([0xa0, 0xcc, 0xb1, 0xfe]) # LDY #$CC, LDA ($FE),Y: $0634 + $CC = $0700
    expect(cpu.a).to eq(0x3c)
  end

  it "reads other (zp),Y instructions' data from the execution segment" do
    bus.poke_bank(2, 0x0634, 0x0f)
    bus.poke(0x0634, 0xf0)
    run([0xa9, 0x00, 0xa0, 0x00, 0x11, 0xfe]) # LDA #0, LDY #0, ORA ($FE),Y
    expect(cpu.a).to eq(0xf0)
  end

  it "reads LDA (zp,X)'s data from the execution segment" do
    bus.poke_bank(2, 0x0634, 0x0f)
    bus.poke(0x0634, 0xf0)
    run([0xa2, 0x00, 0xa1, 0xfe]) # LDX #0, LDA ($FE,X)
    expect(cpu.a).to eq(0xf0)
  end

  it "goes back to the execution segment after the indirect access" do
    bus.poke(0x0634, 0x11)
    run([0xa0, 0x00, 0xb1, 0xfe, 0xad, 0x34, 0x06]) # LDY #0, LDA ($FE),Y, LDA $0634
    expect(cpu.a).to eq(0x11)
  end

  # CPU/cputest/6509.bas: the code it pokes to $0201 and $0100 compares
  # segments 0 and 1 at $0200 through (zp),Y, and leaves 1 at $0200 of
  # the execution segment on a 6509.
  describe "6509.bas's detection" do
    let(:detector) do
      [120, 165, 1, 72, 165, 0, 72, 165, 254, 72, 165, 255, 72, 169, 0, 133, 254, 168, 162, 1, 169,
       2, 133, 255, 132, 1, 177, 254, 141, 0, 2, 134, 1, 177, 254, 205, 0, 2, 208, 18, 73, 255,
       132, 1, 145, 254, 141, 0, 2, 134, 1, 177, 254, 205, 0, 2, 240, 5, 162, 1, 76, 0, 1, 162, 0, 76, 0, 1]
    end
    let(:restorer) do
      [132, 1, 173, 0, 2, 73, 255, 145, 254, 104, 133, 255, 104, 133, 254, 104, 133, 0, 104, 133, 1, 142, 0, 2,
       88, 96]
    end

    before do
      detector.each_with_index { |byte, i| bus.poke(0x0201 + i, byte) }
      restorer.each_with_index { |byte, i| bus.poke(0x0100 + i, byte) }
      bus.poke_bank(0, 0x0200, 0x5a)
      bus.poke_bank(1, 0x0200, 0x5a)
      cpu.stack_pointer = 0xf0
      bus.poke(0x01f1, 0xff) # RTS to $0400
      bus.poke(0x01f2, 0x03)
      cpu.program_counter = 0x0201
    end

    it "finds a 6509" do
      cpu.step! until cpu.program_counter == 0x0400
      expect(bus.peek(0x0200)).to eq(1)
    end
  end
end
