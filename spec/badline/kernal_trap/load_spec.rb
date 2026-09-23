# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::KernalTrap::Load do
  let(:computer) { Badline::Computer.new }
  let(:ram) { computer.ram }
  let(:dir) { Dir.mktmpdir }
  let(:capture) { computer.capture_output }

  before do
    File.binwrite(File.join(dir, "DATA.PRG"), [0x00, 0xc0, 0xaa, 0xbb].pack("C*"))
    computer.mount(Badline::Storage::HostDirectory.new(dir))
    capture
    # CLRCHN is JMP ($0322) and CHROUT is JMP ($0326); point both at an RTS
    ram.write(0x0322, [0x00, 0x60])
    ram.write(0x0326, [0x00, 0x60])
    ram.poke(0x6000, 0x60)
    ram.poke(0x9d, 0x00)
  end

  after { FileUtils.remove_entry(dir) }

  def request_load(name, device: 8, secondary: 1)
    ram.write(0x0340, name.bytes)
    ram.write(0xbb, [0x40, 0x03])
    ram.poke(0xb7, name.length)
    ram.poke(0xba, device)
    ram.poke(0xb9, secondary)
    push_return_address(0x1234)
  end

  def push_return_address(addr)
    ram.write(0x01fe, [addr & 0xff, addr >> 8])
    computer.cpu.stack_pointer = 0xfd
  end

  def trigger_trap
    computer.cpu.program_counter = described_class::ADDRESS
    computer.cpu.cycle!
  end

  def run_trap
    trigger_trap
    500.times do
      break if computer.cpu.program_counter == 0x1235

      computer.cpu.step!
    end
  end

  def direct_mode
    ram.poke(0x9d, 0x80)
  end

  describe "a load to the embedded address" do
    before do
      request_load("DATA")
      run_trap
    end

    specify { expect(ram.read(0xc000, 2)).to eq([0xaa, 0xbb]) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xff) }
    specify { expect(computer.cpu.status.carry?).to be(false) }
    specify { expect(computer.cpu.x).to eq(0x02) }
    specify { expect(computer.cpu.y).to eq(0xc0) }
    specify { expect(ram.read(0xae, 2)).to eq([0x02, 0xc0]) }
    specify { expect(ram.peek(0x90)).to eq(0x40) }
  end

  describe "returning to the caller" do
    before do
      ram.write(0x1235, [0xa9, 0x42]) # LDA #$42
      request_load("DATA")
      run_trap
      computer.cpu.step!
    end

    specify { expect(computer.cpu.a).to eq(0x42) }
  end

  describe "a relocated load" do
    before do
      ram.write(0xc3, [0x00, 0x60])
      request_load("DATA", secondary: 0)
      run_trap
    end

    specify { expect(ram.read(0x6000, 2)).to eq([0xaa, 0xbb]) }
    specify { expect(computer.cpu.x).to eq(0x02) }
    specify { expect(computer.cpu.y).to eq(0x60) }
  end

  describe "a PETSCII shifted-letter filename" do
    before do
      request_load("\xC4\xC1\xD4\xC1".b) # "DATA" with shifted letters
      run_trap
    end

    specify { expect(ram.read(0xc000, 2)).to eq([0xaa, 0xbb]) }
  end

  describe "a drive-prefixed filename" do
    before do
      request_load("0:DATA")
      run_trap
    end

    specify { expect(ram.read(0xc000, 2)).to eq([0xaa, 0xbb]) }
  end

  describe "a filename with type and mode fields" do
    before do
      request_load("DATA,P,R")
      run_trap
    end

    specify { expect(ram.read(0xc000, 2)).to eq([0xaa, 0xbb]) }
  end

  describe "a verify request" do
    before do
      request_load("DATA")
      computer.cpu.a = 1
      run_trap
    end

    specify { expect(ram.peek(0xc000)).to eq(0) }
    specify { expect(computer.cpu.status.carry?).to be(false) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xff) }
    specify { expect(ram.peek(0x90)).to eq(0x50) }
  end

  describe "a verify request that matches memory" do
    before do
      ram.write(0xc000, [0xaa, 0xbb])
      request_load("DATA")
      computer.cpu.a = 1
      run_trap
    end

    specify { expect(ram.peek(0x90)).to eq(0x40) }
  end

  describe "a missing file" do
    before do
      request_load("NOPE")
      run_trap
    end

    specify { expect(computer.cpu.status.carry?).to be(true) }
    specify { expect(computer.cpu.a).to eq(0x04) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xff) }
    specify { expect(ram.peek(0x90)).to eq(0x42) }
  end

  describe "an empty filename" do
    before do
      request_load("")
      run_trap
    end

    specify { expect(computer.cpu.a).to eq(0x08) }
    specify { expect(computer.cpu.status.carry?).to be(true) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xff) }
  end

  describe "messages in program mode" do
    before do
      request_load("DATA")
      run_trap
    end

    specify { expect(capture.output).to eq("") }
  end

  describe "messages for a load in direct mode" do
    before do
      direct_mode
      request_load("DATA")
      run_trap
    end

    specify { expect(capture.output).to eq("\nsearching for data\nloading") }
    specify { expect(computer.cpu.status.carry?).to be(false) }
    specify { expect(computer.cpu.x).to eq(0x02) }
    specify { expect(computer.cpu.y).to eq(0xc0) }
  end

  describe "messages for a verify in direct mode" do
    before do
      direct_mode
      request_load("DATA")
      computer.cpu.a = 1
      run_trap
    end

    specify { expect(capture.output).to eq("\nsearching for data\nverifying") }
  end

  describe "messages for a missing file in direct mode" do
    before do
      direct_mode
      request_load("NOPE")
      run_trap
    end

    specify { expect(capture.output).to eq("\nsearching for nope") }
    specify { expect(computer.cpu.a).to eq(0x04) }
  end

  describe "messages for an empty filename in direct mode" do
    before do
      direct_mode
      request_load("")
      run_trap
    end

    specify { expect(capture.output).to eq("") }
  end

  describe "a load from another device" do
    before do
      request_load("DATA", device: 1)
      trigger_trap
    end

    specify { expect(ram.peek(0xc000)).to eq(0) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
  end

  describe "with the KERNAL ROM banked out" do
    before do
      computer.address_bus.poke(0x00, 0x2f)
      computer.address_bus.poke(0x01, 0x35)
      request_load("DATA")
      trigger_trap
    end

    specify { expect(ram.peek(0xc000)).to eq(0) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
  end
end
