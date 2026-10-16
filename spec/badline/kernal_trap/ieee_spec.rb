# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::KernalTrap::IEEE do
  let(:model) { "8032" }
  let(:computer) { Badline::PET.new(model:) }
  let(:dir) { Dir.mktmpdir }

  before do
    File.binwrite(File.join(dir, "DATA.PRG"), [0x00, 0xc0, 0xaa, 0xbb].pack("C*"))
    computer.mount(Badline::Storage::HostDirectory.new(dir))
    computer.poke(zero_page.device, 8)
    # The editor's set-up of the VIA's port B: NRFD, ATN, the cassette
    # write line and motor 2 driven high.
    computer.poke(0xe840, 0x1e)
    computer.poke(0xe842, 0x1e)
  end

  after { FileUtils.remove_entry(dir) }

  def layout = computer.model.trap_layout

  def zero_page = layout.zero_page

  def cpu = computer.cpu

  def call_routine(routine, acc = 0)
    computer.poke(0x01fe, 0x34)
    computer.poke(0x01ff, 0x12)
    computer.poke(0x1235, 0xea) # NOP
    cpu.stack_pointer = 0xfd
    cpu.a = acc
    cpu.program_counter = layout.public_send(routine)
    cpu.cycle!
    cpu.step!
  end

  # The PET's TALK and LISTEN address the device in FA, whatever A holds.
  def send_frame(secondary, bytes = [])
    call_routine(:listen)
    call_routine(:second, secondary)
    bytes.each { |byte| call_routine(:ciout, byte) }
    call_routine(:unlisten)
  end

  def read_bytes(secondary, count, address: :tksa)
    call_routine(:talk)
    call_routine(address, 0x60 | secondary)
    bytes = Array.new(count) do
      call_routine(:acptr)
      cpu.a
    end
    call_routine(:untalk)
    bytes
  end

  def status = computer.peek(zero_page.status)

  describe "an open frame" do
    before { send_frame(0xf2, "DATA".bytes) }

    it "returns to the caller" do
      expect(cpu.stack_pointer).to eq(0xff)
    end

    it "serves the file through the channel TKSA names" do
      expect(read_bytes(2, 4)).to eq([0x00, 0xc0, 0xaa, 0xbb])
    end

    it "serves it through the channel SECOND names after TALK, as BASIC 2's LOAD sends it" do
      expect(read_bytes(2, 4, address: :second)).to eq([0x00, 0xc0, 0xaa, 0xbb])
    end

    it "raises EOI with the last byte" do
      read_bytes(2, 4)
      expect(status).to eq(0x40)
    end

    it "reports a read timeout past the end" do
      read_bytes(2, 5)
      expect(status).to eq(0x42)
    end
  end

  describe "a close frame" do
    before { send_frame(0xf2, "DATA".bytes) }

    it "empties the channel" do
      send_frame(0xe2)
      expect(read_bytes(2, 1)).to eq([0x0d])
    end

    it "closes it with no UNLISTEN after it, as BASIC 1's CLOSE sends it" do
      call_routine(:listen)
      call_routine(:second, 0xe2)
      expect(read_bytes(2, 1)).to eq([0x0d])
    end
  end

  describe "a SAVE's channel" do
    before do
      send_frame(0xf1, "SAVED".bytes)
      send_frame(0x61, [0x01, 0x04, 0x60])
      send_frame(0xe1)
    end

    it "saves a program in a host directory" do
      expect(File.binread(File.join(dir, "saved.prg")).bytes).to eq([0x01, 0x04, 0x60])
    end
  end

  describe "a frame for another device" do
    before do
      computer.poke(zero_page.device, 9)
      call_routine(:listen, 8)
    end

    it "leaves it to the ROM" do
      expect(cpu.stack_pointer).to eq(0xfd)
    end
  end

  describe "the lines the ROM drives" do
    def port_b = computer.peek(0xe840)

    it "holds ATN low after TALK" do
      call_routine(:talk)
      expect(port_b & 0x04).to eq(0)
    end

    it "lets ATN go after TKSA, leaving A as written to the port" do
      call_routine(:talk)
      call_routine(:tksa, 0x6f)
      expect([port_b & 0x04, cpu.a & 0x04]).to eq([0x04, 0x04])
    end

    it "pulls NDAC low through PIA 2's CA2 after TKSA" do
      call_routine(:talk)
      call_routine(:tksa, 0x6f)
      expect(computer.pia2.ca2_output).to be(false)
    end

    it "lets every line go after UNTALK" do
      read_bytes(15, 1)
      expect([port_b & 0x06, computer.pia2.ca2_output, computer.pia2.cb2_output]).to eq([0x06, true, true])
    end

    it "times each byte on VIA timer 1" do
      send_frame(0x6f, "I0".bytes)
      expect(computer.via.timer1_latch >> 8).to eq(0xff)
    end
  end

  describe "the flags ACPTR leaves" do
    before { send_frame(0xf2, "DATA".bytes) }

    it "sets N for a byte with bit 7 set" do
      call_routine(:talk)
      call_routine(:tksa, 0x62)
      2.times { call_routine(:acptr) }
      expect(cpu.status.negative?).to be(true)
    end
  end

  context "with BASIC 1" do
    let(:model) { "2001" }

    it "leaves the UNLISTEN command in FA" do
      send_frame(0x6f, "I0".bytes)
      expect(computer.peek(zero_page.device)).to eq(0x3f)
    end

    it "leaves the UNTALK command in FA" do
      read_bytes(15, 1)
      expect(computer.peek(zero_page.device)).to eq(0x5f)
    end
  end

  context "with an 8096's board over the KERNAL" do
    let(:model) { "8096" }

    before do
      computer.poke(0xfff0, 0x80)
      computer.poke(layout.listen, 0xea) # NOP
      call_routine(:listen)
    end

    it "leaves the RAM there to run" do
      expect(cpu.stack_pointer).to eq(0xfd)
    end
  end
end
