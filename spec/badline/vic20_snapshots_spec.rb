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

    # A machine in the middle of its boot, restored from a State taken once
    # for each RAM configuration.
    def saved(ram) = described_class.restored(TakenOnce.fetch([:vic20_booting, ram]) { booting(ram).snapshot })

    def digest(machine) = [machine.snapshot, machine.video.display.hash]

    described_class::Bus::RAM_CONFIGURATIONS.each_key do |ram|
      it "restores a machine with #{ram} RAM that runs on as the saved one" do
        machine = booting(ram)
        restored = described_class.restored(machine.snapshot)
        [machine, restored].each { |each_machine| each_machine.run_cycles(60_000) }
        expect(digest(restored)).to eq(digest(machine))
      end
    end

    it "carries the keys still to be typed over" do
      machine = described_class.new.tap { |typing| typing.type_text("print 6*7\r") }
      machine.run_cycles(machine.init_threshold + 1)
      restored = described_class.restored(machine.snapshot)
      [machine, restored].each { |each_machine| each_machine.run_cycles(200_000) }
      expect(digest(restored)).to eq(digest(machine))
    end

    it "carries a cartridge's ROM over" do
      machine = saved(:unexpanded).tap { |with_rom| with_rom.bus.map_rom(0xa000, Array.new(0x2000, 0xaa)) }
      expect(described_class.restored(machine.snapshot).bus.peek(0xa000)).to eq(0xaa)
    end

    it "carries the disk device 8 serves over" do
      machine = saved(:unexpanded)
      Badline::Media.attach(machine, blank_d64(File.join(Dir.mktmpdir, "blank.d64")), autostart: false)
      expect(described_class.restored(machine.snapshot).mounted?).to be(true)
    end

    it "carries a true 1541 over, running on as the saved one" do
      machine = described_class.new.tap { |with_drive| Badline::Media::TrueDrive.plug(with_drive) }
      machine.run_cycles(400_001)
      restored = described_class.restored(machine.snapshot)
      [machine, restored].each { |each_machine| each_machine.run_cycles(60_000) }
      expect(digest(restored)).to eq(digest(machine))
    end

    it "carries the tape and its place over" do
      machine = saved(:unexpanded)
      tape = File.join(Dir.mktmpdir, "game.tap")
      File.binwrite(tape, "C64-TAPE-RAW".b + [1, 0, 0, 0, 3].pack("C4V") + "\x30\x40\x50".b)
      Badline::Media.attach(machine, tape, autostart: false)
      expect(described_class.restored(machine.snapshot).datasette.tape.bytes).to eq(machine.datasette.tape.bytes)
    end

    it "saves to a .vsf whose machine is VIC20" do
      saved(:unexpanded).save_snapshot(path)
      expect(Badline::Snapshot.read(path).container.machine).to eq("VIC20")
    end

    it "loads a VIC-20 from its .vsf" do
      machine = saved(:"16k")
      machine.save_snapshot(path)
      loaded = Badline::Snapshot.load(path)
      expect([loaded.class, loaded.ram_configuration,
              loaded.snapshot]).to eq([described_class, :"16k", machine.snapshot])
    end

    it "reports the on_init handlers the saved machine had yet to run" do
      described_class.new.tap { |machine| machine.type_text("run\r") }.save_snapshot(path)
      lines = []
      Badline::Snapshot.load(path) { |line| lines << line }
      expect(lines).to eq(["1 on_init handler(s) the saved machine had yet to run, left out"])
    end

    it "takes a machine back to the state" do
      machine = saved(:unexpanded)
      state = machine.snapshot
      machine.run_cycles(1_000)
      expect(machine.restore(state).snapshot).to eq(state)
    end

    it "refuses a state with other RAM" do
      expect { described_class.new.restore(described_class.new(ram: :"8k").snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /8k/)
    end

    it "leaves the machine as it was when it refuses a state" do
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

    it "refuses a C64's state" do
      expect { described_class.new.restore(Badline::Computer.new.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /expected VIC20/)
    end

    it "refuses a VIC20 snapshot without the BADLINE module" do
      File.binwrite(path, Badline::Snapshot::Container.new([], machine: "VIC20").to_s)
      expect { Badline::Snapshot.load(path) }.to raise_error(Badline::Snapshot::FormatError, /xvic/)
    end
  end
end
