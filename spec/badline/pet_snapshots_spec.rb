# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/taken_once"

describe Badline::PET do
  describe "snapshots" do
    let(:path) { File.join(Dir.mktmpdir, "pet.vsf") }

    # A machine run part way through its KERNAL's reset.
    def booting(model) = described_class.new(model:).tap { |machine| machine.run_cycles(20_001) }

    # A machine part way through its reset, restored from a snapshot taken
    # once for each model.
    def saved(model) = TakenOnce.fetch([:pet_booting_image, model]) { booting(model).snapshot }.load

    def digest(machine) = [machine.snapshot, machine.video.display.hash]

    %w[8032 2001].each do |model|
      it "restores a #{model} that runs on as the saved one, picture and all" do
        machine = booting(model)
        restored = machine.snapshot.load
        [machine, restored].each { |each_machine| each_machine.run_cycles(20_000) }
        expect(digest(restored)).to eq(digest(machine))
      end
    end

    it "saves to a .vsf whose machine is PET, with badline's modules alone" do
      saved("8032").save_snapshot(path)
      snapshot = Badline::Snapshot.read(path)
      expect([snapshot.container.machine, snapshot.sections.map(&:name)])
        .to eq(["PET", %w[BL-MACHINE BL-CPU BL-RAM BL-PIA1 BL-PIA2 BL-VIA BL-CRTC BL-VIDEO BL-TAPE1 BL-TAPE2]])
    end

    it "saves a 2001 without a CRTC" do
      expect(saved("2001").snapshot.sections.map(&:name))
        .to eq(%w[BL-MACHINE BL-CPU BL-RAM BL-PIA1 BL-PIA2 BL-VIA BL-VIDEO BL-TAPE1 BL-TAPE2])
    end

    it "loads a 2001 from its .vsf" do
      machine = saved("2001")
      machine.save_snapshot(path)
      loaded = Badline::Snapshot.load(path)
      expect([loaded.class, loaded.model.name, loaded.refresh_hz, loaded.snapshot])
        .to eq([described_class, "2001", 60, machine.snapshot])
    end

    it "carries the screen RAM over" do
      machine = saved("8032").tap { |pet| pet.poke(0x8123, 0x42) }
      expect(machine.snapshot.load.peek(0x8123)).to eq(0x42)
    end

    context "with an 8096's board" do
      let(:machine) do
        described_class.new(model: "8096").tap do |pet|
          pet.poke(0xfff0, 0x84)
          pet.poke(0x9000, 0x5a)
        end
      end

      it "carries the banks and the control register over" do
        restored = machine.snapshot.load
        expect([restored.bus.expansion.control, restored.peek(0x9000)]).to eq([0x84, 0x5a])
      end

      it "lays the banks over the pages the control register picks" do
        machine.poke(0xfff0, 0x80)
        expect(machine.snapshot.load.peek(0x9000)).to eq(0)
      end
    end

    context "with an 8296's board" do
      let(:machine) do
        described_class.new(model: "8296", characters: "din", jumpers: %w[userport]).tap do |pet|
          pet.poke(0xc000, 0x5a)
          pet.poke(0xe843, 0x07)
          pet.poke(0xe841, 0x03)
        end
      end

      it "carries the RAM under the ROMs and the user port lines that show it over" do
        expect(machine.snapshot.load.peek(0xc000)).to eq(0x5a)
      end

      it "builds the machine with the same jumpers and character ROM" do
        restored = machine.snapshot.load
        expect([restored.jumpers, restored.model.characters]).to eq([%w[userport], "pet/characters-din.rom"])
      end
    end

    it "carries the disk in device 8 over" do
      machine = saved("8032")
      machine.mount(Badline::Storage::D64Image.new("game.d64", read_only: true, bytes: Array.new(174_848, 0)))
      restored = machine.snapshot.load
      expect([restored.mounted?, File.basename(restored.mounted_path)]).to eq([true, "game.d64"])
    end

    # A machine with a tape playing in the datasette at cassette port #2.
    def playing_deck2
      bytes = "C64-TAPE-RAW".bytes + [1, 3, 0, 0, 4, 0, 0, 0, 0x30, 0x30, 0x30, 0x30]
      saved("8032").tap do |machine|
        machine.cassettes.datasette2.insert(Badline::Storage::TAP.new("deck2.tap", bytes:))
        machine.cassettes.datasette2.play!
      end
    end

    it "carries each datasette's tape and keys over" do
      restored = playing_deck2.snapshot.load.cassettes
      expect([restored.datasette1.tape, File.basename(restored.datasette2.tape.path), restored.datasette2.playing?])
        .to eq([nil, "deck2.tap", true])
    end

    it "reports the on_init handlers the saved machine had yet to run" do
      described_class.new.tap { |machine| machine.type_text("run\r") }.save_snapshot(path)
      lines = []
      Badline::Snapshot.load(path) { |line| lines << line }
      expect(lines).to eq(["1 on_init handler(s) the saved machine had yet to run, left out"])
    end

    it "takes a machine back to the snapshot" do
      machine = saved("8032")
      image = machine.snapshot
      machine.run_cycles(1_000)
      expect(machine.restore(image).snapshot).to eq(image)
    end

    it "refuses a snapshot of another model" do
      expect { described_class.new.restore(described_class.new(model: "4032").snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /of a 4032 with 32K at 50 Hz, not a 8032 with 32K at 50 Hz/)
    end

    it "refuses a snapshot with other RAM" do
      expect { described_class.new(model: "3032").restore(described_class.new(model: "3032", ram_kb: 16).snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /16K/)
    end

    it "refuses a snapshot of the editor for another frame rate" do
      expect { described_class.new.restore(described_class.new(refresh_hz: 60).snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /at 60 Hz, not/)
    end

    it "restores a 2001 upgraded to BASIC 2 with its ROMs" do
      described_class.new(model: "2001", basic: "2").save_snapshot(path)
      expect(Badline::Snapshot.load(path).model.basic).to eq("pet/basic2.rom")
    end

    it "refuses a snapshot of ROMs it doesn't fit" do
      out = Badline::Snapshot::Keyed::Writer.new.text("family", "pet").text("rom.basic", "pet/basic2.rom")
      setup = Badline::Snapshot::PETSetup.read_fields(Badline::Snapshot::Keyed::Reader.parse(out.section("BL-MACHINE")))
      expect { setup.build.load_modules(Badline::Snapshot::Keyed::Modules.new([out.section("BL-MACHINE")])) }
        .to raise_error(Badline::Snapshot::FormatError, %r{running pet/basic2.rom})
    end

    it "refuses a C64's snapshot" do
      expect { described_class.new.restore(Badline::C64.new.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /of a C64, not a PET/)
    end

    it "refuses a PET snapshot with neither badline's modules nor xpet's memory" do
      File.binwrite(path, Badline::Snapshot::Container.new([], machine: "PET").to_s)
      expect { Badline::Snapshot.load(path) }.to raise_error(Badline::Snapshot::FormatError, /no PETMEM module/)
    end

    it "exports a snapshot with xpet's modules ahead of badline's" do
      described_class.new.export_snapshot(path)
      names = Badline::Snapshot::Container.parse(File.binread(path)).sections.map(&:name)
      expect(names.values_at(0, 7, 10)).to eq(%w[MAINCPU FSDRIVE BL-MACHINE])
    end
  end
end
