# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::KernalTrap::Serial do
  let(:computer) { Badline::Computer.new }
  let(:ram) { computer.ram }
  let(:cpu) { computer.cpu }
  let(:dir) { Dir.mktmpdir }

  before do
    File.binwrite(File.join(dir, "DATA.PRG"), [0x00, 0xc0, 0xaa, 0xbb].pack("C*"))
    computer.mount(Badline::Storage::HostDirectory.new(dir))
  end

  after { FileUtils.remove_entry(dir) }

  def call_routine(routine, acc)
    ram.write(0x01fe, [0x34, 0x12])
    ram.poke(0x1235, 0xea) # NOP
    cpu.stack_pointer = 0xfd
    cpu.a = acc
    cpu.program_counter = described_class::ROUTINES.key(routine)
    cpu.cycle!
    cpu.step!
  end

  def send_frame(secondary, bytes = [], device: 8)
    call_routine(:listen, device)
    call_routine(:second, secondary)
    bytes.each { |byte| call_routine(:ciout, byte) }
    call_routine(:unlisten, 0x3f)
  end

  def read_bytes(secondary, count)
    call_routine(:talk, 8)
    call_routine(:tksa, 0x60 | secondary)
    bytes = Array.new(count) do
      call_routine(:acptr, 0)
      cpu.a
    end
    call_routine(:untalk, 0x5f)
    bytes
  end

  describe "an open frame" do
    before { send_frame(0xf2, "DATA".bytes) }

    it "returns to the caller" do
      expect(cpu.stack_pointer).to eq(0xff)
    end

    it "serves the file through the channel" do
      expect(read_bytes(2, 4)).to eq([0x00, 0xc0, 0xaa, 0xbb])
    end

    it "raises EOI with the last byte" do
      read_bytes(2, 4)
      expect(ram.peek(0x90)).to eq(0x40)
    end

    it "reports a read timeout past the end" do
      read_bytes(2, 5)
      expect(ram.peek(0x90)).to eq(0x42)
    end
  end

  describe "a close frame" do
    before do
      send_frame(0xf2, "DATA".bytes)
      send_frame(0xe2)
    end

    it "empties the channel" do
      expect(read_bytes(2, 1)).to eq([0x0d])
    end
  end

  describe "the command channel" do
    before { send_frame(0x6f, "I0\r".bytes) }

    it "returns the status message" do
      expect(read_bytes(15, 12).pack("C*")).to eq("00, OK,00,00")
    end
  end

  describe "a shifted PETSCII filename" do
    before { send_frame(0xf2, "\xC4\xC1\xD4\xC1".b.bytes) }

    it "folds the name to ASCII" do
      expect(read_bytes(2, 4)).to eq([0x00, 0xc0, 0xaa, 0xbb])
    end
  end

  describe "a memory command in an open frame" do
    before do
      send_frame(0xff, [*"M-W".bytes, 0x00, 0x05, 1, 0xc1])
      send_frame(0x6f, [*"M-R".bytes, 0x00, 0x05, 1])
    end

    it "passes the binary arguments through unfolded" do
      expect(read_bytes(15, 1)).to eq([0xc1])
    end
  end

  describe "a frame for another device" do
    before { send_frame(0xf2, "DATA".bytes, device: 4) }

    it "leaves the stack untouched" do
      expect(cpu.stack_pointer).to eq(0xfd)
    end

    it "opens nothing on the drive" do
      expect(read_bytes(2, 1)).to eq([0x0d])
    end
  end

  describe "with the KERNAL ROM banked out" do
    before do
      computer.address_bus.poke(0x00, 0x2f)
      computer.address_bus.poke(0x01, 0x35)
      ram.poke(described_class::ROUTINES.key(:listen), 0xea) # NOP
      call_routine(:listen, 8)
    end

    it "falls through to the underlying RAM" do
      expect(cpu.stack_pointer).to eq(0xfd)
    end
  end
end
