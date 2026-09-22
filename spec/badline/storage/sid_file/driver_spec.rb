# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# BASIC's READY loop reuses $19-$21, so a stub that returned to it would
# clobber zero page the tune owns between init and the first play. The
# caller at $c100 stands in for BASIC: it SYSes the stub, then marks $c001
# and scribbles on $19.
describe Badline::Storage::SIDFile::Driver do
  let(:dir) { Dir.mktmpdir }
  let(:tune) { Badline::Storage::SIDFile.new(File.join(dir, "tune.sid")) }
  let(:computer) { Badline::Computer.new }

  before do
    File.binwrite(File.join(dir, "tune.sid"), (header + image).pack("C*"))
    computer.ram.write(tune.load_address, tune.data)
    computer.ram.write(tune.driver_address, tune.driver)
    computer.ram.write(0xc100, basic_stand_in)
    computer.cpu.program_counter = 0xc100
    (Badline::Audio::BarePlayer::FRAME_CYCLES * 3).times { computer.cycle! }
  end

  after { FileUtils.remove_entry(dir) }

  def header
    fields = [2, 0x7c, 0x1000, 0x1000, 0x1010, 1, 1]
    "PSID".bytes + fields.pack("n7").bytes + ([0] * 100) +
      [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  end

  # init: lda #$3f / sta $19 / rts, and at $1010 play: lda $19 / sta $c000 / rts
  def image
    [0xa9, 0x3f, 0x85, 0x19, 0x60] + ([0xea] * 11) +
      [0xa5, 0x19, 0x8d, 0x00, 0xc0, 0x60]
  end

  # jsr $0334 / lda #$0a / sta $c001 / sta $19 / jmp *
  def basic_stand_in
    [0x20, 0x34, 0x03, 0xa9, 0x0a, 0x8d, 0x01, 0xc0, 0x85, 0x19, 0x4c, 0x0a, 0xc1]
  end

  it "never returns to the caller" do
    expect(computer.ram.peek(0xc001)).to eq(0)
  end

  it "keeps the zero page init wrote for play" do
    expect(computer.ram.peek(0xc000)).to eq(0x3f)
  end
end
