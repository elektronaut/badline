# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../support/blank_disk"
require_relative "../support/snapshot_scenarios"

describe Badline::Snapshot do
  include BlankDisk
  include SnapshotScenarios

  let(:computer) { saved_demo }
  let(:path) { File.join(Dir.mktmpdir, "machine.vsf") }

  describe ".load" do
    before { computer.save_snapshot(path) }

    it "restores the machine as it was saved" do
      expect(described_class.load(path).snapshot).to eq(SnapshotScenarios.demo_state)
    end

    it "builds the machine as the saved one was built" do
      Badline::Computer.new(vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580).save_snapshot(path)
      restored = described_class.load(path)
      expect([restored.vic.model, restored.cia1.model, restored.sid.model]).to eq(%i[mos8565 mos6526a mos8580])
    end

    it "reports on_init handlers the saved machine had yet to run" do
      Badline::Computer.new.tap { |machine| machine.type_text("run\r") }.save_snapshot(path)
      lines = []
      described_class.load(path) { |line| lines << line }
      expect(lines).to eq(["1 on_init handler(s) the saved machine had yet to run, left out"])
    end
  end

  describe "#restore_snapshot" do
    let(:target) { run(Badline::Computer.new, 3_001) }

    before { computer.save_snapshot(path) }

    it "takes a running machine back to the snapshot" do
      target.restore_snapshot(path)
      expect(target.snapshot).to eq(SnapshotScenarios.demo_state)
    end

    it "reports nothing left out" do
      expect(target.restore_snapshot(path).ignored).to be_empty
    end
  end

  describe ".read" do
    before { computer.save_snapshot(path) }

    it "reads a badline snapshot's modules" do
      expect(described_class.read(path).sections.map(&:name))
        .to eq(%w[MAINCPU C64MEM C64CART CIA1 CIA2 SID SIDEXTENDED FSDRIVE VIC-II GLUE C64MEMHACKS TAPEPORT
                  JOYPORT0 JOYSTICK0 JOYPORT1 JOYSTICK1 USERPORT BADLINE])
    end

    it "knows a snapshot badline wrote" do
      expect(described_class.read(path)).to be_badline
    end
  end

  it "leaves the saved machine alone" do
    computer.save_snapshot(path)
    expect(computer.snapshot).to eq(SnapshotScenarios.demo_state)
  end

  Badline::Model::ALL.reject { |model| model.region == Badline::Region::PAL }.each do |model|
    describe "the #{model.name}" do
      let(:computer) do
        run(demo_machine(**model.to_h.except(:name)), SnapshotScenarios::DEMO_CYCLES)
      end

      before { computer.save_snapshot(path) }

      it "is built again as it was" do
        expect(Badline::Model.of(Badline::Snapshot::Setup.of(described_class.load(path).address_bus))).to eq(model)
      end

      it "runs on as the saved machine does" do
        restored = described_class.load(path)
        expect(run(restored, 40_000).snapshot).to eq(run(computer, 40_000).snapshot)
      end
    end
  end

  describe "a machine with an REU part way through a transfer" do
    # A 512K REU swapping $0800 bytes at $0400 with its RAM at $2000 in
    # bank 3, with the interrupt on the end of the block enabled.
    let(:computer) do
      run(demo_machine(reu: 512), SnapshotScenarios::DEMO_CYCLES).tap do |machine|
        bus = machine.address_bus
        { 0xdf02 => 0x00, 0xdf03 => 0x04, 0xdf04 => 0x00, 0xdf05 => 0x20, 0xdf06 => 0x03, 0xdf07 => 0x00,
          0xdf08 => 0x08, 0xdf09 => 0xc0, 0xdf01 => 0x92 }.each { |addr, value| bus.poke(addr, value) }
        run(machine, 1_001)
      end
    end

    before { computer.save_snapshot(path) }

    it "is saved with the transfer under way" do
      expect(computer.reu).to be_holds_bus
    end

    it "is built again with an REU of the same size" do
      expect(described_class.load(path).reu.size_kb).to eq(512)
    end

    it "runs on as the saved machine does" do
      restored = described_class.load(path)
      expect(run(restored, 40_000).snapshot).to eq(run(computer, 40_000).snapshot)
    end
  end

  describe "with a tape whose file is gone" do
    before do
      tape = File.join(Dir.mktmpdir, "gone.tap")
      File.binwrite(tape, "C64-TAPE-RAW".b + [1, 0, 0, 0, 1].pack("C4V") + "\x30".b)
      computer.datasette.insert(Badline::Storage::TAP.new(tape))
      computer.save_snapshot(path)
      File.delete(tape)
    end

    it "puts the tape back in from the snapshot" do
      expect(described_class.load(path).datasette.tape.bytes).to eq(computer.datasette.tape.bytes)
    end
  end

  describe "saving once a medium's file is gone" do
    let(:dir) { Dir.mktmpdir }
    let(:machine) { Badline::Computer.new }

    after { FileUtils.rm_rf(dir) }

    def tape
      File.join(dir, "gone.tap").tap do |file|
        File.binwrite(file, "C64-TAPE-RAW".b + [1, 0, 0, 0, 1].pack("C4V") + "\x30".b)
      end
    end

    def archive
      File.join(dir, "gone.t64").tap { |file| File.binwrite(file, "C64S tape image file".ljust(0x40, "\0").b) }
    end

    def disk = File.join(dir, "gone.d64").tap { |file| blank_d64(file) }

    def save_without(file)
      run(machine, 300_001)
      FileUtils.rm_rf(file)
      described_class.save(machine, path)
    end

    it "saves a machine with a tape in" do
      file = tape
      machine.datasette.insert(Badline::Storage::TAP.new(file))
      expect(save_without(file)).to eq(path)
    end

    it "saves a machine serving a .t64 as device 8" do
      file = archive
      machine.mount(Badline::Storage::T64.new(file))
      expect(save_without(file)).to eq(path)
    end

    it "saves a machine serving a directory as device 8" do
      machine.mount(Badline::Storage::HostDirectory.new(dir))
      expect(save_without(dir)).to eq(path)
    end

    it "saves a machine with a disk in a true 1541" do
      Badline::Media::TrueDrive.plug(machine)
      file = disk
      Badline::Media.attach(machine, file, autostart: false)
      expect(save_without(file)).to eq(path)
    end
  end

  it "fails on a damaged gzipped file" do
    File.binwrite(path, "\x1f\x8b".b + ("\0" * 20))
    expect { described_class.load(path) }.to raise_error(Badline::Snapshot::FormatError, /gzipped snapshot is damaged/)
  end

  it "fails on a file that isn't a snapshot" do
    File.binwrite(path, "not a snapshot")
    expect { described_class.load(path) }.to raise_error(Badline::Snapshot::FormatError, /not a VICE snapshot/)
  end
end
