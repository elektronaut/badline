# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::KernalTrap::Save do
  let(:computer) { Badline::Computer.new }
  let(:ram) { computer.ram }
  let(:dir) { Dir.mktmpdir }
  let(:backend) { Badline::Storage::HostDirectory.new(dir) }
  let(:capture) { computer.capture_output }

  before do
    computer.mount(backend)
    capture
    ram.write(0xc000, [0xaa, 0xbb])
    # CLRCHN is JMP ($0322) and CHROUT is JMP ($0326); point both at an RTS
    ram.write(0x0322, [0x00, 0x60])
    ram.write(0x0326, [0x00, 0x60])
    ram.poke(0x6000, 0x60)
    ram.poke(0x9d, 0x00)
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
    specify { expect(ram.peek(0xb9)).to eq(0x61) }
    specify { expect(ram.read(0xac, 2)).to eq([0x02, 0xc0]) }
  end

  describe "a save the host can't write", :file_permissions do
    before do
      File.chmod(0o555, dir)
      request_save("DATA")
      run_trap
    end

    after { File.chmod(0o755, dir) }

    specify { expect(saved_file("data.prg")).to be_nil }
    specify { expect(computer.cpu.stack_pointer).to eq(0xff) }
    specify { expect(computer.cpu.status.carry?).to be(false) }
    specify { expect(ram.peek(0x90)).to eq(0x80) }
  end

  describe "messages for a save the host can't write in direct mode" do
    before do
      allow(backend).to receive(:write_file).and_return(false)
      direct_mode
      request_save("DATA")
      run_trap
    end

    specify { expect(capture.output).to eq("\nsaving data") }
    specify { expect(computer.cpu.status.carry?).to be(false) }
  end

  describe "the registers the ROM leaves" do
    before do
      request_save("DATA")
      computer.cpu.x = 0xc1
      computer.cpu.y = 0xc0
      ram.poke(0x90, 0x80)
      run_trap
    end

    specify { expect(computer.cpu.x).to eq(0xc1) }
    specify { expect(computer.cpu.y).to eq(0x00) }
    specify { expect(computer.cpu.a).to eq(computer.address_bus.peek(0xdd00) & 0xdf) }
    specify { expect(computer.cpu.status.overflow?).to be(true) }
    specify { expect(ram.peek(0x90)).to eq(0x00) }
  end

  describe "releasing the serial clock and data lines" do
    before do
      computer.address_bus.poke(0xdd02, 0x3f)
      computer.address_bus.poke(0xdd00, 0x37)
      request_save("DATA")
      run_trap
    end

    specify { expect(computer.address_bus.peek(0xdd00) & 0x30).to eq(0) }
  end

  describe "messages in program mode" do
    before do
      request_save("DATA")
      run_trap
    end

    specify { expect(capture.output).to eq("") }
  end

  describe "messages in direct mode" do
    before do
      direct_mode
      request_save("DATA")
      run_trap
    end

    specify { expect(capture.output).to eq("\nsaving data") }
    specify { expect(saved_file("data.prg")).to eq([0x00, 0xc0, 0xaa, 0xbb]) }
    specify { expect(computer.cpu.y).to eq(0x00) }
    specify { expect(computer.cpu.status.carry?).to be(false) }
  end

  describe "messages for an empty filename in direct mode" do
    before do
      direct_mode
      request_save("")
      run_trap
    end

    specify { expect(capture.output).to eq("") }
    specify { expect(computer.cpu.a).to eq(0x08) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xff) }
  end

  describe "a save after an interrupted one" do
    before do
      direct_mode
      request_save("DATA")
      trigger_trap
      computer.reset!
      ram.poke(0x9d, 0x80)
      request_save("MORE")
      run_trap
    end

    specify { expect(saved_file("more.prg")).to eq([0x00, 0xc0, 0xaa, 0xbb]) }
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
    def vector
      [computer.address_bus.peek(0xfffe), computer.address_bus.peek(0xffff)]
    end

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

  describe "a filename with type and mode fields" do
    before do
      request_save("DATA,P,W")
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
      trigger_trap
    end

    specify { expect(saved_file("data.prg")).to be_nil }
    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
  end

  describe "with the KERNAL ROM banked out" do
    before do
      computer.address_bus.poke(0x00, 0x2f)
      computer.address_bus.poke(0x01, 0x35)
      request_save("DATA")
      trigger_trap
    end

    specify { expect(saved_file("data.prg")).to be_nil }
    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
  end

  describe "a read-only storage backend" do
    let(:backend) { Class.new { def read_file(_name) = nil }.new }

    before do
      request_save("DATA")
      trigger_trap
    end

    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
  end
end
