# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/blank_disk"
require_relative "../support/taken_once"

describe Badline::Vic20 do
  include BlankDisk

  describe "snapshots" do
    let(:path) { File.join(Dir.mktmpdir, "vic20.vsf") }

    # A machine run to the middle of its boot.
    def booting(ram) = described_class.new(ram:).tap { |machine| machine.run_cycles(400_001) }

    # A machine in the middle of its boot, restored from a snapshot taken
    # once for each RAM configuration.
    def saved(ram) = TakenOnce.fetch([:vic20_booting_image, ram]) { booting(ram).snapshot }.load

    def digest(machine) = [machine.snapshot, machine.video.display.hash]

    def vic_record(machine) = machine.snapshot.sections.find { |section| section.name == "BL-VICI" }

    described_class::Bus::RAM_CONFIGURATIONS.each_key do |ram|
      it "restores a machine with #{ram} RAM that runs on as the saved one" do
        machine = booting(ram)
        restored = machine.snapshot.load
        [machine, restored].each { |each_machine| each_machine.run_cycles(60_000) }
        expect(digest(restored)).to eq(digest(machine))
      end
    end

    it "carries the keys still to be typed over" do
      machine = described_class.new.tap { |typing| typing.type_text("print 6*7\r") }
      machine.run_cycles(machine.init_threshold + 1)
      restored = machine.snapshot.load
      [machine, restored].each { |each_machine| each_machine.run_cycles(200_000) }
      expect(digest(restored)).to eq(digest(machine))
    end

    it "saves the same VIC record whether or not the host played and drained the sound" do
      played, silent = Array.new(2) { described_class.new.tap { |machine| machine.run_cycles(400_001) } }
      played.sound_source.record(rate: 44_100)
      [played, silent].each { |machine| machine.vic.poke(0x900c, 0xf3) && machine.run_cycles(30_000) }
      played.sound_source.drain_samples
      expect(vic_record(played)).to eq(vic_record(silent))
    end

    it "carries a cartridge's ROM over" do
      machine = saved(:unexpanded).tap { |with_rom| with_rom.bus.map_rom(0xa000, Array.new(0x2000, 0xaa)) }
      expect(machine.snapshot.load.bus.peek(0xa000)).to eq(0xaa)
    end

    it "carries the cartridge's name over" do
      machine = saved(:unexpanded).tap { |with_rom| with_rom.bus.map_rom(0xa000, Array.new(0x2000, 0xaa)) }
      machine.bus.cartridge_name = "GAME"
      expect(machine.snapshot.load.cartridge_name).to eq("GAME")
    end

    it "loads a cartridge saved without a name as unnamed" do
      bus = saved(:unexpanded).bus.tap { |named| named.cartridge_name = "GAME" }
      bus.load_rom_fields(Badline::Snapshot::Keyed::Reader.new("BL-CART"))
      expect(bus.cartridge_name).to eq("")
    end

    it "carries the disk device 8 serves over" do
      machine = saved(:unexpanded)
      Badline::Media.attach(machine, blank_d64(File.join(Dir.mktmpdir, "blank.d64")), autostart: false)
      expect(machine.snapshot.load.mounted?).to be(true)
    end

    it "carries a true 1541 over, running on as the saved one" do
      machine = described_class.new.tap { |with_drive| Badline::Media::TrueDrive.plug(with_drive) }
      machine.run_cycles(400_001)
      restored = machine.snapshot.load
      [machine, restored].each { |each_machine| each_machine.run_cycles(60_000) }
      expect(digest(restored)).to eq(digest(machine))
    end

    it "carries the tape and its place over" do
      machine = saved(:unexpanded)
      tape = File.join(Dir.mktmpdir, "game.tap")
      File.binwrite(tape, "C64-TAPE-RAW".b + [1, 0, 0, 0, 3].pack("C4V") + "\x30\x40\x50".b)
      Badline::Media.attach(machine, tape, autostart: false)
      expect(machine.snapshot.load.datasette.tape.bytes).to eq(machine.datasette.tape.bytes)
    end

    it "saves to a .vsf whose machine is VIC20, with badline's modules alone" do
      saved(:unexpanded).save_snapshot(path)
      snapshot = Badline::Snapshot.read(path)
      expect([snapshot.container.machine, snapshot.sections.map(&:name)])
        .to eq(["VIC20", %w[BL-MACHINE BL-RAM BL-COLORRAM BL-CPU BL-VICI BL-VIA1 BL-VIA2 BL-TAPE]])
    end

    it "loads a VIC-20 from its .vsf" do
      machine = saved(:"16k")
      machine.save_snapshot(path)
      loaded = Badline::Snapshot.load(path)
      expect([loaded.class, loaded.ram_configuration,
              loaded.snapshot]).to eq([described_class, :"16k", machine.snapshot])
    end

    it "reports the on_init handlers the saved machine had yet to run" do
      described_class.new.tap { |machine| machine.on_init { nil } }.save_snapshot(path)
      lines = []
      Badline::Snapshot.load(path) { |line| lines << line }
      expect(lines).to eq(["1 on_init handler(s) the saved machine had yet to run, left out"])
    end

    it "takes a machine back to the snapshot" do
      machine = saved(:unexpanded)
      image = machine.snapshot
      machine.run_cycles(1_000)
      expect(machine.restore(image).snapshot).to eq(image)
    end

    it "refuses a snapshot with other RAM" do
      expect { described_class.new.restore(described_class.new(ram: :"8k").snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /8k/)
    end

    it "refuses a snapshot of the other model" do
      expect { described_class.new.restore(described_class.new(model: "ntsc").snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /of an? NTSC VIC-20, not a PAL one/)
    end

    it "restores an NTSC VIC-20 in its short interlaced field that runs on as the saved one" do
      machine = described_class.new(model: "ntsc").tap { |ntsc| ntsc.poke(0x9000, 0x85) }
      machine.run_cycles(65 * (261 + 263 + 10))
      restored = machine.snapshot.load
      [machine, restored].each { |each_machine| each_machine.run_cycles(65 * 300) }
      expect([restored.vic.rasterline, *digest(restored)]).to eq([machine.vic.rasterline, *digest(machine)])
    end

    it "builds the NTSC model a snapshot names" do
      image = described_class.new(model: "ntsc").snapshot
      expect(image.load.model).to eq("ntsc")
    end

    it "leaves the machine as it was when it refuses a snapshot" do
      machine = saved(:unexpanded)
      before = machine.snapshot
      refused { machine.restore(described_class.new(ram: :"8k").snapshot) }
      expect(machine.snapshot).to eq(before)
    end

    def refused
      yield
    rescue Badline::Snapshot::FormatError
      nil
    end

    it "refuses a C64's snapshot" do
      expect { described_class.new.restore(Badline::C64.new.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /of a C64, not a VIC-20/)
    end

    it "refuses a VIC20 snapshot without badline's modules" do
      File.binwrite(path, Badline::Snapshot::Container.new([], machine: "VIC20").to_s)
      expect { Badline::Snapshot.load(path) }.to raise_error(Badline::Snapshot::FormatError, /xvic/)
    end
  end
end
