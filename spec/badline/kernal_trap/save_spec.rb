# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::KernalTrap::Save do
  let(:computer) { Badline::Computer.new }
  let(:ram) { computer.ram }
  let(:dir) { Dir.mktmpdir }
  let(:backend) { Badline::Storage::HostDirectory.new(dir) }

  before do
    computer.mount(backend)
    ram.write(0xc000, [0xaa, 0xbb])
  end

  after { FileUtils.remove_entry(dir) }

  def request_save(name, device: 8, from: 0xc000, upto: 0xc002)
    ram.write(0x0340, name.bytes)
    ram.write(0xbb, [0x40, 0x03])
    ram.poke(0xb7, name.length)
    ram.poke(0xba, device)
    ram.write(0xc1, [from & 0xff, from >> 8])
    ram.write(0xae, [upto & 0xff, upto >> 8])
    push_return_address(0x1234)
  end

  def push_return_address(addr)
    ram.write(0x01fe, [addr & 0xff, addr >> 8])
    computer.cpu.stack_pointer = 0xfd
  end

  def run_trap
    computer.cpu.program_counter = described_class::ADDRESS
    computer.cpu.cycle!
  end

  def saved_file(name)
    path = File.join(dir, name)
    File.binread(path).bytes if File.exist?(path)
  end

  describe "saving a memory range" do
    before do
      request_save("DATA")
      run_trap
    end

    specify { expect(saved_file("data.prg")).to eq([0x00, 0xc0, 0xaa, 0xbb]) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xff) }
    specify { expect(computer.cpu.status.carry?).to be(false) }
    specify { expect(ram.peek(0x90)).to eq(0x00) }
  end

  describe "returning to the caller" do
    before do
      ram.write(0x1235, [0xa9, 0x42]) # LDA #$42
      request_save("DATA")
      run_trap
      computer.cpu.step!
    end

    specify { expect(computer.cpu.a).to eq(0x42) }
  end

  describe "a PETSCII shifted-letter filename" do
    before do
      request_save("\xC4\xC1\xD4\xC1".b) # "DATA" with shifted letters
      run_trap
    end

    specify { expect(saved_file("data.prg")).to eq([0x00, 0xc0, 0xaa, 0xbb]) }
  end

  describe "a range wrapping through $FFFF" do
    let(:vector) { [computer.address_bus.peek(0xfffe), computer.address_bus.peek(0xffff)] }

    before do
      request_save("WRAP", from: 0xfffe, upto: 0x0000)
      run_trap
    end

    it "reads through the memory map, KERNAL ROM included" do
      expect(saved_file("wrap.prg")).to eq([0xfe, 0xff, *vector])
    end
  end

  describe "a save-with-replace drive prefix" do
    before do
      request_save("@0:DATA")
      run_trap
    end

    specify { expect(saved_file("data.prg")).to eq([0x00, 0xc0, 0xaa, 0xbb]) }
  end

  describe "a bare drive prefix with no name" do
    before do
      request_save("@0:")
      run_trap
    end

    specify { expect(computer.cpu.a).to eq(0x08) }
    specify { expect(computer.cpu.status.carry?).to be(true) }
  end

  describe "an empty filename" do
    before do
      request_save("")
      run_trap
    end

    specify { expect(computer.cpu.a).to eq(0x08) }
    specify { expect(computer.cpu.status.carry?).to be(true) }
    specify { expect(saved_file(".prg")).to be_nil }
  end

  describe "a save to another device" do
    before do
      request_save("DATA", device: 1)
      run_trap
    end

    specify { expect(saved_file("data.prg")).to be_nil }
    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
  end

  describe "with the KERNAL ROM banked out" do
    before do
      computer.address_bus.poke(0x00, 0x2f)
      computer.address_bus.poke(0x01, 0x35)
      request_save("DATA")
      run_trap
    end

    specify { expect(saved_file("data.prg")).to be_nil }
    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
  end

  describe "a read-only storage backend" do
    let(:backend) { Class.new { def read_file(_name) = nil }.new }

    before do
      request_save("DATA")
      run_trap
    end

    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
  end
end
