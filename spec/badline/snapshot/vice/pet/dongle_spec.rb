# frozen_string_literal: true

require "spec_helper"

# xpet 3.10's 6702 bytes, the PETMEM settings from their fifth byte,
# dumped from its monitor after writes to $EFE0.
module XpetDongleSamples
  WRITES = [0x93, 0x10, 0xf9, 0x91, 0xec, 0x83, 0x7e, 0xc2, 0xad, 0x64, 0xd7, 0x3c, 0x2a, 0x00, 0xae, 0xaf, 0x73,
            0xfa, 0xf1, 0xaa, 0x93, 0x3b, 0x72, 0x3d, 0xf5, 0xc1, 0x07, 0x93, 0x89, 0xda, 0x27, 0xed, 0xc0, 0x5e,
            0xae, 0x72, 0x9f, 0x02, 0x2d, 0x62].freeze

  # After WRITES.
  AFTER_WRITES = [0x67, 0x2d, 0x01, 0x01, 0x00, 0x07, 0x00, 0x11, 0x00, 0xcb, 0x00, 0x01, 0x00, 0x04, 0x00, 0x0e,
                  0x00, 0x01, 0x00].freeze

  # After $00, then $01.
  AFTER_ONE_SHIFT = [0xc6, 0x01, 0x00, 0x10, 0x00, 0x02, 0x00, 0x20, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x08,
                     0x00, 0x01, 0x00].freeze
end

describe Badline::Snapshot::Vice::PET::Dongle do
  let(:clock) { Struct.new(:cycles).new(0) }
  let(:dongle) { Badline::PET::SuperPET::Dongle.new(clock) }

  def written(values)
    values.each do |value|
      clock.cycles += 10
      dongle.poke(0xefe0, value)
    end
    clock.cycles += 10
    dongle
  end

  def exported = described_class.export(dongle.settled_registers, dongle.latch)

  def imported(bytes)
    out = Badline::Snapshot::Keyed::Writer.new
    described_class.import(bytes, out)
    Badline::Snapshot::Keyed::Reader.new("BL-SUPERPET", out.to_s)
  end

  it "writes the 6702 after one shift as xpet does" do
    written([0x00, 0x01])
    expect(exported).to eq(XpetDongleSamples::AFTER_ONE_SHIFT)
  end

  it "reads the registers xpet saved, and D0 clear in the last write" do
    fields = imported(XpetDongleSamples::AFTER_WRITES)
    expect([fields.ints("dongle.registers", []), fields.int("dongle.latch", 0xff)])
      .to eq([written(XpetDongleSamples::WRITES).registers, 0x00])
  end

  it "reads back the registers it writes" do
    written(XpetDongleSamples::WRITES)
    expect(imported(exported).ints("dongle.registers", [])).to eq(dongle.registers)
  end

  it "writes a shift that hasn't happened yet as done" do
    written([0x00]).poke(0xefe0, 0x01)
    pending = exported
    clock.cycles += 10
    dongle.peek(0xefe0)
    expect(pending).to eq(exported)
  end
end
