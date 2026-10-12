# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/taken_once"

describe Badline::Plus4 do
  describe "snapshots" do
    let(:path) { File.join(Dir.mktmpdir, "plus4.vsf") }

    # A machine run part way through its KERNAL's reset.
    def booting(model) = described_class.new(model:).tap { |machine| machine.run_cycles(20_001) }

    # A machine part way through its reset, restored from a snapshot taken
    # once for each model.
    def saved(model) = TakenOnce.fetch([:plus4_booting_image, model]) { booting(model).snapshot }.load

    def digest(machine) = [machine.snapshot, machine.ted.display.hash]

    %w[plus4 c16].each do |model|
      it "restores a #{model} that runs on as the saved one" do
        machine = booting(model)
        restored = machine.snapshot.load
        [machine, restored].each { |each_machine| each_machine.run_cycles(12_000) }
        expect(digest(restored)).to eq(digest(machine))
      end
    end

    it "carries the keys still to be typed over", :slow do
      machine = described_class.new.tap { |typing| typing.type_text("print 6*7\r") }
      machine.run_cycles(machine.init_threshold + 1)
      restored = machine.snapshot.load
      [machine, restored].each { |each_machine| each_machine.run_cycles(40_000) }
      expect(digest(restored)).to eq(digest(machine))
    end

    it "carries a cartridge's ROMs over" do
      machine = saved("plus4")
      machine.bus.attach_cartridge([Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 1, address: 0xc000,
                                                                        data: [0xaa] * 0x4000)])
      machine.bus.select_banks(0xfd0c)
      expect(machine.snapshot.load.peek(0xc000)).to eq(0xaa)
    end

    it "carries the TCBM interface's TIAs over" do
      machine = described_class.new(tcbm: true).tap { |plus4| plus4.tias[0].poke(0xfee0, 0x42) }
      expect(machine.snapshot.load.tias[0].ports[0]).to eq(0x42)
    end

    it "saves to a .vsf whose machine is PLUS4, with badline's modules alone" do
      saved("plus4").save_snapshot(path)
      snapshot = Badline::Snapshot.read(path)
      expect([snapshot.container.machine, snapshot.sections.map(&:name)])
        .to eq(["PLUS4", %w[BL-MACHINE BL-CPU BL-TED BL-TEDSOUND BL-KEYPORT BL-USERPORT BL-ACIA BL-RAM BL-TAPE]])
    end

    it "saves a C16 without the Plus/4's own parts" do
      names = saved("c16").snapshot.sections.map(&:name)
      expect(names).to eq(%w[BL-MACHINE BL-CPU BL-TED BL-TEDSOUND BL-KEYPORT BL-RAM BL-TAPE])
    end

    it "loads a C16 from its .vsf" do
      machine = saved("c16")
      machine.save_snapshot(path)
      loaded = Badline::Snapshot.load(path)
      expect([loaded.class, loaded.model.name, loaded.ram_kb, loaded.snapshot])
        .to eq([described_class, "c16", 16, machine.snapshot])
    end

    it "reports the on_init handlers the saved machine had yet to run" do
      described_class.new.tap { |machine| machine.type_text("run\r") }.save_snapshot(path)
      lines = []
      Badline::Snapshot.load(path) { |line| lines << line }
      expect(lines).to eq(["1 on_init handler(s) the saved machine had yet to run, left out"])
    end

    it "takes a machine back to the snapshot" do
      machine = saved("plus4")
      image = machine.snapshot
      machine.run_cycles(1_000)
      expect(machine.restore(image).snapshot).to eq(image)
    end

    it "refuses a snapshot of another model" do
      expect { described_class.new.restore(described_class.new(model: "c16").snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /of a c16 with 16K, not a plus4 with 64K/)
    end

    it "refuses a snapshot with other RAM" do
      expect { described_class.new.restore(described_class.new(ram: 32).snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /32K/)
    end

    it "leaves the machine as it was when it refuses a snapshot" do
      machine = saved("plus4")
      before = machine.snapshot
      refused { machine.restore(described_class.new(model: "c16").snapshot) }
      expect(machine.snapshot).to eq(before)
    end

    def refused
      yield
    rescue Badline::Snapshot::FormatError
      nil
    end

    it "refuses a C64's snapshot" do
      expect { described_class.new.restore(Badline::C64.new.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, %r{of a C64, not a Plus/4})
    end

    it "refuses a PLUS4 snapshot without badline's modules" do
      File.binwrite(path, Badline::Snapshot::Container.new([], machine: "PLUS4").to_s)
      expect { Badline::Snapshot.load(path) }.to raise_error(Badline::Snapshot::FormatError, /xplus4/)
    end

    it "refuses to export a snapshot for VICE" do
      expect { described_class.new.export_snapshot(path) }
        .to raise_error(Badline::Snapshot::FormatError, %r{doesn't export a Plus/4's snapshot for VICE})
    end
  end
end
