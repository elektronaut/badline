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

  describe "a file the host can't read" do
    before do
      File.chmod(0o000, File.join(dir, "DATA.PRG"))
      request_load("DATA")
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

  describe "a file on a disk image with an error table" do
    let(:drive) { Badline::KernalTrap::Drive.new(Badline::Storage::D64Image.new(image_path)) }

    def write_image(bad_sector)
      bytes = Array.new(174_848, 0)
      entry = ((17 * 21) + 1) * 256 # track 18, sector 1
      bytes[entry + 2, 19] = [0x82, 17, 0, *"BAD".bytes, *([0xa0] * 13)]
      block = 16 * 21 * 256 # track 17, sector 0
      bytes[block, 256] = [17, 1, 0x00, 0xc0, *([0xaa] * 252)]
      bytes[block + 256, 4] = [0, 3, 0xbb, 0xbb]
      errors = Array.new(683, 1)
      errors[(16 * 21) + bad_sector] = 5
      File.binwrite(image_path, (bytes + errors).pack("C*"))
    end

    def image_path
      File.join(dir, "bad.d64")
    end

    def mount_image(bad_sector)
      write_image(bad_sector)
      trap = described_class.new(cpu: computer.cpu, bus: computer.address_bus, drive:)
      computer.cpu.install_trap(described_class::ADDRESS) { trap.call }
    end

    def status
      message = []
      loop do
        byte, eoi = drive.read(15)
        message << byte
        break if eoi
      end
      message.pack("C*").chomp("\r")
    end

    def run_cycles(count)
      count.times do
        break if computer.cpu.program_counter == 0x1235

        computer.cycle!
      end
    end

    before { ram.write(0x0328, [0xed, 0xf6]) } # the STOP vector, as the KERNAL sets it

    context "when a later block is bad" do
      before do
        mount_image(1)
        request_load("BAD")
        trigger_trap
        run_cycles(20_000)
      end

      it "loads the bytes the drive sent before the bad block" do
        expect(ram.read(0xc000, 252)).to eq(([0xaa] * 251) + [0x00])
      end

      it "keeps waiting for the next byte" do
        expect(computer.cpu.program_counter).not_to eq(0x1235)
      end

      it "reports the block's error on the command channel" do
        expect(status).to eq("23,READ ERROR,17,01")
      end

      it "breaks off on RUN/STOP" do
        ram.poke(0x91, 0x7f)
        run_cycles(20_000)
        expect([computer.cpu.program_counter, computer.cpu.a, computer.cpu.status.carry?]).to eq([0x1235, 0, true])
      end
    end

    context "when the first block is bad" do
      before do
        mount_image(0)
        request_load("BAD")
        run_trap
      end

      specify { expect(computer.cpu.a).to eq(0x04) }
      specify { expect(computer.cpu.status.carry?).to be(true) }
      specify { expect(ram.peek(0x90)).to eq(0x42) }
      specify { expect(status).to eq("23,READ ERROR,17,00") }
    end
  end

  describe "a load over the KERNAL vectors" do
    def run_until(address)
      trigger_trap
      5000.times do
        break if computer.cpu.program_counter == address

        computer.cpu.step!
      end
    end

    before do
      # ISTOP at $0328 points at the ROM's STOP; the file replaces its high
      # byte, so the byte loop's next STOP call lands at $C0ED
      File.binwrite(File.join(dir, "VECTOR.PRG"), [0x29, 0x03, 0xc0, 0x11].pack("C*"))
      ram.write(0x0328, [0xed, 0xf6])
      request_load("VECTOR")
      run_until(0xc0ed)
    end

    specify { expect(computer.cpu.program_counter).to eq(0xc0ed) }
    specify { expect(ram.read(0x0329, 2)).to eq([0xc0, 0x00]) }
  end

  describe "a relocated load over the zero page" do
    before do
      ram.write(0xc3, [0x02, 0x00])
      request_load("DATA", secondary: 0)
      trigger_trap
    end

    specify { expect(ram.read(0x02, 2)).not_to eq([0xaa, 0xbb]) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xfd) }
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
