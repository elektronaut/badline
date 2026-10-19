# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../support/blank_disk"

# The routines' calling convention and the file control block are the
# Waterloo ROM's, after opsys-all-clean-20101210-src.txt.
describe Badline::PET::SuperPET::WaterlooTraps do
  include BlankDisk

  subject(:superpet) { Badline::PET::SuperPET.new(cpu: "6809") }

  let(:dir) { Dir.mktmpdir }
  let(:traps) { described_class }

  # A file control block at $0500 for device 8, channel 2.
  let(:block) { 0x0500 }

  before do
    path = blank_d64(File.join(dir, "w.d64"))
    Badline::Storage::D64Image.new(path).write_file("HELLO", [0x11, 0x22, 0x33])
    superpet.mount(Badline::Storage::D64Image.new(path))
    [[block, 0], [block + 9, 8], [block + 10, 2], [block + 12, 0]].each { |addr, value| superpet.poke(addr, value) }
  end

  after { FileUtils.remove_entry(dir) }

  # Whether a trap returns in place of the routine at +address+, called
  # with D, and +pushed+ words above the return address $1234 on the
  # stack, for one cycle.
  def trapped?(address, value = 0, *pushed)
    cpu = superpet.m6809
    [0x12, 0x34, *pushed.flat_map { |word| [word >> 8, word & 0xff] }].each_with_index do |byte, index|
      superpet.poke(0x0900 + index, byte)
    end
    cpu.s = 0x0900
    cpu.d = value
    cpu.pc = address
    cpu.resume(cpu.cycles)
    cpu.cycle!
    cpu.s == 0x0902
  end

  # Opens the file named on channel 2 as the ROM's ieeeOpen does, and
  # returns the name sent.
  def open_file(name)
    trapped?(traps::SET_LISTENER, block, 0x00f0)
    sent = "#{name},PRG"
    sent.each_byte { |byte| trapped?(traps::BYTE_OUT, byte) }
    trapped?(traps::UNLISTEN)
    sent
  end

  # The bytes the talker sends, each with the EOI bit it leaves in the
  # block's byte 12.
  def read_bytes(count)
    trapped?(traps::SET_TALKER, block)
    Array.new(count) do
      trapped?(traps::BYTE_IN)
      [superpet.m6809.b, superpet.peek(block + 12) & 0x01]
    end
  end

  it "returns from SetLstnr for device 8, with the bus at $77-$7A listening" do
    trapped?(traps::SET_LISTENER, block, 0x00f0)
    expect(Array.new(4) { |offset| superpet.peek(0x77 + offset) }).to eq([0x20, 0xf0, 8, 2])
  end

  it "opens a file named on drive 1 from the disk and reads it to its end" do
    open_file("1:HELLO")
    expect(read_bytes(3)).to eq([[0x11, 0], [0x22, 0], [0x33, 1]])
  end

  it "times out a read past the end in the block's status" do
    open_file("1:HELLO")
    read_bytes(4)
    expect(superpet.peek(block)).to eq(3)
  end

  it "leaves another device to the ROM" do
    superpet.poke(block + 9, 9)
    expect(trapped?(traps::SET_LISTENER, block, 0x00f0)).to be(false)
  end

  it "leaves a routine a language hooks to the ROM" do
    superpet.poke(0x0580 + 27, 0xff)
    expect(trapped?(traps::SET_LISTENER, block, 0x00f0)).to be(false)
  end

  it "leaves device 8 to a true drive there" do
    superpet.plug_true_drive
    expect(trapped?(traps::SET_LISTENER, block, 0x00f0)).to be(false)
  end

  it "goes when the disk comes out" do
    superpet.unmount
    expect(trapped?(traps::SET_LISTENER, block, 0x00f0)).to be(false)
  end

  describe "with the menu up", :slow do
    # A program in the Waterloo loader's blocks: one that loads at $1000
    # and writes OK at $8000, then the block that ends the load.
    let(:program) do
      code = [0x8e, 0x80, 0x00, 0x86, 0x4f, 0xa7, 0x80, 0x86, 0x4b, 0xa7, 0x84, 0x20, 0xfe]
      [0x10, 0x00, 0x00, code.length, 0, 0, *code, 0, 0, 0, 0, 2, 0]
    end

    # A disk with the program on it as "hello".
    let(:disk) do
      path = blank_d64(File.join(dir, "p.d64"))
      Badline::Storage::D64Image.new(path).write_file("hello", program)
      Badline::Storage::D64Image.new(path)
    end

    it "loads and runs a program the menu is typed the name of, from device 8" do
      superpet.mount(disk)
      superpet.type_text("hello\r")
      superpet.run_cycles(900_000)
      expect([superpet.peek(0x8000), superpet.peek(0x8001), superpet.m6809.pc]).to eq([0x4f, 0x4b, 0x100c])
    end
  end
end
