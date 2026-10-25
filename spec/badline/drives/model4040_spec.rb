# frozen_string_literal: true

require "spec_helper"
require "badline/drives/model4040"
require "tmpdir"
require_relative "../../support/taken_once"

describe Badline::Drives::Model4040 do
  subject(:drive) { described_class.new }

  def blank_d64(dir)
    File.join(dir, "blank.d64").tap do |path|
      File.binwrite(path, "\0" * 174_848)
      Badline::Storage::D64Image.new(path).format("blank", "ab".bytes)
    end
  end

  describe "the interface processor's bus" do
    let(:bus) { drive.ip_bus }

    it "finds DOS 2.1's ROM at $D000 and again at $5000" do
      expect(bus.peek(0x5000)).to eq(bus.peek(0xd000))
    end

    it "repeats the 6532s and the common RAM every 32 KB" do
      bus.poke(0x9005, 0x5a)
      expect([bus.peek(0x1005), bus.peek(0x8285)]).to eq([0x5a, bus.peek(0x0285)])
    end

    it "reads open bus where a ROM socket is empty" do
      bus = described_class::IPBus.new(rom: Badline::ROM.new(Array.new(0x2000, 0xea), length: 0x2000, start: 0xe000),
                                       common: Badline::Memory.new([], length: 0x1000),
                                       data_riot: drive.data_riot, control_riot: drive.control_riot)
      bus.poke(0x1000, 0x42)
      expect(bus.peek(0xd000)).to eq(0x42)
    end
  end

  describe "its controller" do
    it "runs 901466-04 from $FC00" do
      expect((0xfc00..0xffff).map { |addr| drive.fdc_bus.peek(addr) }).to eq(Badline::ROM.read("4040/fdc-901466-04.rom"))
    end

    it "takes no interrupt from the VIA" do
      drive.via.poke(0x4e, 0xff)
      drive.via.ca1 = false
      drive.cycle!
      expect([drive.via.irq?, drive.fdc_cpu.irq]).to eq([true, false])
    end
  end

  describe "a disk" do
    let(:disk) { Dir.mktmpdir { |dir| described_class::Disk.new(Badline::Storage::D64Image.new(blank_d64(dir))) } }

    it "turns the 16 MHz clock's cells per zone" do
      expect([1, 18, 25, 31].map { |track| disk.track(track).length }).to eq([6153, 5714, 5333, 5000])
    end

    it "lays a sector out as DOS 2.1's format writes it" do
      sync = described_class::Disk::SYNC
      expect(disk.track(1).first(25)).to eq(([sync] * 4) + [0x08, 1 ^ 0x61 ^ 0x62, 0, 1, 0x62, 0x61] + ([0] * 9) +
                                            ([sync] * 4) + [0x07, 0])
    end

    it "has no track past 35" do
      expect(disk.track(36)).to be_nil
    end
  end

  describe "the mechanism" do
    let(:mechanism) { drive.mechanism }

    def step_drive0(*counts)
      counts.each do |count|
        drive.via.poke(0x42, 0xff)
        drive.via.poke(0x40, (0xff & ~0x0c) | (count << 2))
        drive.cycle!
      end
    end

    it "moves drive 0's head half a track in for each count up" do
      step_drive0(1, 2, 3, 0)
      expect([mechanism.half_tracks[0], mechanism.track]).to eq([4, 3])
    end

    it "moves it out for each count down, as far as track 1" do
      step_drive0(1, 2, 1, 0, 3)
      expect(mechanism.half_tracks[0]).to eq(0)
    end

    it "reads SYNC low on the 6530's PB6 while a sync passes" do
      expect(drive.rriot.peek(0x02).anybits?(0x40)).to be(true)
    end

    context "with drive 0's motor turning" do
      before do
        drive.via.poke(0x42, 0xff)
        drive.via.poke(0x40, 0xdf)
      end

      it "is quiet with no disk in it" do
        drive.cycle!
        expect(mechanism).to be_quiet
      end

      it "isn't with a disk in it" do
        Dir.mktmpdir { |dir| drive.insert_image(blank_d64(dir)) }
        drive.cycle!
        expect(mechanism).not_to be_quiet
      end
    end
  end

  describe "a DOS 1 disk" do
    let(:disk) do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "blank.d67")
        File.binwrite(path, "  # The 4040 and the 3040 switched on alone run on into their idle loops,
" * 176_640)
        Badline::Storage::D67Image.new(path).format("blank", "ab".bytes)
        described_class::Disk.new(Badline::Storage::D67Image.new(path))
      end
    end

    it "lays a sector out as DOS 1 writes it, one cell between header and data" do
      sync = described_class::Disk::SYNC
      expect(disk.track(1).first(13)).to eq([sync, sync, 0x08, 1 ^ 0x61 ^ 0x62, 0, 1, 0x62, 0x61, 0x08, sync, sync,
                                             0x07, 0])
    end

    it "holds 20 sectors on track 18" do
      expect(disk.track(18).count(0x07)).to be >= 20
    end
  end

  describe Badline::Drives::Model2040 do
    subject(:drive) { described_class.new }

    it "finds DOS 1.2 at $E000, with its vectors at the top" do
      expect([drive.ip_bus.peek(0xfffe), drive.ip_bus.peek(0xffff)]).to eq([0xd6, 0xe2])
    end

    it "reads open bus where UJ1 would be" do
      drive.ip_bus.poke(0x1000, 0x5a)
      expect(drive.ip_bus.peek(0xd000)).to eq(0x5a)
    end

    it "runs 901466-02 in the controller's 6530" do
      expect((0xfc00..0xffff).map { |addr| drive.fdc_bus.peek(addr) }).to eq(Badline::ROM.read("4040/fdc-901466-02.rom"))
    end
  end

  # The 4040 and the 3040 switched on alone run on into their idle loops,
  # each pass of their jobs empty.
  describe "booting", :slow do
    def booted(model)
      TakenOnce.fetch([:model4040_boot, model]) { model.new.tap { |unit| 800_000.times { unit.cycle! } } }
    end

    it "brings the IP to DOS 2.1's idle loop" do
      expect(booted(described_class).ip_cpu.program_counter).to be_between(0xd4b7, 0xd507)
    end

    it "brings the 3040's to its own" do
      expect(booted(Badline::Drives::Model3040).ip_cpu.program_counter).to be_between(0xd4b8, 0xd508)
    end

    it "brings the 2040's to DOS 1.2's, with no handshake" do
      expect(booted(Badline::Drives::Model2040).ip_cpu.program_counter).to be_between(0xe27e, 0xe2d5)
    end

    it "tells the IP the controller's period in $0400" do
      expect(booted(described_class).common.peek(0)).to eq(0x0f)
    end
  end
end
