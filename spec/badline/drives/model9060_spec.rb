# frozen_string_literal: true

require "spec_helper"
require "badline/drives/model9060"
require "tmpdir"
require "fileutils"
require_relative "../../support/taken_once"

describe Badline::Drives::Model9060 do
  subject(:drive) { described_class.new(dos_rom: stub_dos, sasi_rom: stub_sasi) }

  # NOPs, with each processor's reset vector at its own RAM.
  let(:stub_dos) do
    bytes = Array.new(0x4000, 0xea)
    bytes[0x3ffc, 2] = [0x00, 0x10]
    Badline::ROM.new(bytes, length: 0x4000, start: 0xc000)
  end

  let(:stub_sasi) do
    Array.new(0x800, 0xea).tap { |bytes| bytes[0x7fc, 2] = [0x00, 0x04] }
  end

  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def blank(size)
    File.join(dir, "#{size}.d90").tap { |path| File.binwrite(path, "\0" * size) }
  end

  describe "the SASI host's bus" do
    let(:bus) { drive.sasi_bus }

    it "puts the 6810 at $00, mirrored at $0100 for the stack" do
      bus.poke(0x017f, 0x5a)
      expect([bus.ram.peek(0x7f), bus.peek(0x007f)]).to eq([0x5a, 0x5a])
    end

    it "puts the VIA at $80" do
      bus.poke(0x0083, 0xff)
      expect(drive.via.peek(0x83)).to eq(0xff)
    end

    it "puts the common RAM at $0400" do
      bus.poke(0x0805, 0x33)
      expect(drive.common.peek(0x0405)).to eq(0x33)
    end

    it "puts 300515 at $F800" do
      expect([bus.peek(0xf800), bus.peek(0xfffc)]).to eq([0xea, 0x00])
    end

    it "reads the last byte on the data bus from open bus" do
      bus.peek(0xf800)
      expect(bus.peek(0x2000)).to eq(0xea)
    end

    it "marks a read of the VIA's interrupt flags volatile" do
      bus.peek(0x008d)
      expect(bus.volatile).to be(true)
    end

    it "leaves a read of the VIA's port A alone" do
      bus.peek(0x0081)
      expect(bus.volatile).to be(false)
    end
  end

  describe "the SASI lines" do
    let(:bus) { drive.sasi_bus }

    # Drives the data bus and raises SEL as 300515 does.
    def select_controller
      bus.poke(0x0083, 0xff)
      bus.poke(0x0081, 0x01)
      bus.poke(0x0082, 0x03)
      bus.poke(0x0080, 0x01)
      drive.cycle!
    end

    it "selects the controller with SEL and bit 0 on the data bus" do
      select_controller
      expect(drive.target).to be_busy
    end

    it "leaves the controller alone while PB0 is an input" do
      bus.poke(0x0081, 0x01)
      drive.cycle!
      expect(drive.target).not_to be_busy
    end

    it "reads BSY and C/D high on port B once selected" do
      select_controller
      expect(bus.peek(0x0080) & 0x0c).to eq(0x0c)
    end

    it "reads J14 high on a D9060 and low on a D9090" do
      d9090 = Badline::Drives::Model9090.new(dos_rom: stub_dos, sasi_rom: stub_sasi)
      expect([bus.peek(0x0080) & 0x10, d9090.sasi_bus.peek(0x0080) & 0x10]).to eq([0x10, 0x00])
    end

    it "flags REQ's rise on CA1" do
      bus.poke(0x008c, 0x01)
      select_controller
      drive.cycle!
      expect(bus.peek(0x008d) & 0x02).to eq(0x02)
    end

    it "answers REQ with ACK as CA2 pulses for a write of ORA" do
      select_controller
      bus.poke(0x008c, 0x0b)
      bus.poke(0x0081, 0x03)
      drive.cycle!
      expect(drive.target.request?).to be(false)
    end

    it "resets the controller as RST rises" do
      select_controller
      bus.poke(0x0080, 0x02)
      drive.cycle!
      expect(drive.target).not_to be_busy
    end
  end

  describe "#insert_image" do
    it "gives a D9090's image six heads in a D9060" do
      drive.insert_image(blank(7_520_256))
      expect(drive.disk.heads).to eq(6)
    end

    it "gives an image of neither size the drive's heads" do
      unit = Badline::Drives::Model9090.new(dos_rom: stub_dos, sasi_rom: stub_sasi)
      unit.insert_image(blank(1_000))
      expect(unit.disk.heads).to eq(6)
    end
  end

  # The unit through its keyed modules, in the middle of a command, loaded
  # into a fresh unit.
  describe "the keyed modules" do
    let(:copy) do
      drive.insert_image(blank(5_013_504))
      200.times { drive.cycle! }
      drive.target.select(0x01)
      3.times { drive.cycle! }
      modules = Badline::Snapshot::Keyed::Modules.new(drive.save_modules([], "BL-D8"))
      described_class.new(dos_rom: stub_dos, sasi_rom: stub_sasi)
                     .tap { |fresh| fresh.load_modules(modules, modules.required("BL-D8"), "BL-D8") }
    end

    it "saves the same modules again" do
      expect(copy.save_modules([], "BL-D8")).to eq(drive.save_modules([], "BL-D8"))
    end

    it "opens the image again from its path" do
      expect(copy.disk.path).to eq(drive.disk.path)
    end
  end

  # The pattern passes of DOS 3.0's N, which the IP skips once Format Unit
  # has put the controller in its fast mode.
  describe "N's pattern passes" do
    subject(:unit) { described_class.new }

    before do
      unit.insert_image(blank(5_013_504))
      target = unit.target
      target.select(0x01)
      [0x04, 0, 0, 0, 1, 0xc0].each do |byte|
        target.clock until target.request?
        target.acknowledge(byte)
      end
      unit.ip_cpu.program_counter = described_class::FORMAT_PASSES
      unit.ip_bus.poke(described_class::PASS, 0)
    end

    it "sends the IP on to the end of the last pass" do
      unit.send(:skip_format_passes)
      expect([unit.ip_cpu.program_counter, unit.ip_bus.peek(described_class::PASS)])
        .to eq([described_class::FORMAT_DONE, 6])
    end
  end

  describe "booting", :slow do
    # The unit after 1.2 million cycles, and how many of the last 200,000
    # it slept through.
    def booted(model)
      TakenOnce.fetch([:model9060_boot, model]) do
        unit = model.new
        1_000_000.times { unit.host_cycle! }
        asleep = 0
        200_000.times do
          unit.host_cycle!
          asleep += 1 if unit.asleep?
        end
        [unit, asleep]
      end
    end

    it "brings the IP to its idle loop and the host to its job loop" do
      unit = booted(described_class).first
      expect([unit.ip_cpu.program_counter, unit.sasi_cpu.program_counter])
        .to match([be_between(0xc131, 0xc19e), be_between(0xf8f1, 0xf90c)])
    end

    it "sleeps once both idle" do
      expect(booted(described_class).last).to be > 150_000
    end

    it "sends a D9090's controller its six heads" do
      expect(booted(Badline::Drives::Model9090).first.target.heads).to eq(6)
    end
  end
end
