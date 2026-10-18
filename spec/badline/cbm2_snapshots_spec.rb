# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/taken_once"

describe Badline::CBM2 do
  describe "snapshots" do
    let(:path) { File.join(Dir.mktmpdir, "cbm2.vsf") }

    # A 610 part way through its KERNAL's reset, past the mains
    # measurement and into the RAM test, where the indirection register
    # walks the segments, restored from a snapshot taken once.
    def saved
      TakenOnce.fetch(:cbm2_booting_image) do
        described_class.new.tap { |machine| machine.run_cycles(300_001) }.snapshot
      end.load
    end

    it "restores a machine that runs on as the saved one" do
      machine = saved
      restored = machine.snapshot.load
      [machine, restored].each { |each_machine| each_machine.run_cycles(20_000) }
      expect(restored.snapshot).to eq(machine.snapshot)
    end

    it "saves to a .vsf whose machine is CBM-II, with badline's modules alone" do
      saved.save_snapshot(path)
      snapshot = Badline::Snapshot.read(path)
      expect([snapshot.container.machine, snapshot.sections.map(&:name)])
        .to eq(["CBM-II", %w[BL-MACHINE BL-CPU BL-RAM BL-CRTC BL-VIDEO BL-SID BL-CIA BL-ACIA BL-TPI1 BL-TPI2]])
    end

    it "builds the model, KERNAL and mains the snapshot names" do
      machine = described_class.new(model: "720", kernal: "03b", mains_hz: 60).snapshot.load
      expect([machine.model.name, machine.kernal, machine.mains_hz]).to eq(["720", "03b", 60])
    end

    it "keeps the segment registers" do
      machine = saved
      expect([machine.bus.execution_segment, machine.bus.indirect_segment]).to eq([15, 1])
    end

    it "keeps a cartridge's ROM" do
      chip = Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0x2000, data: [0x5a] * 0x2000)
      machine = described_class.new.tap { |cartridge| cartridge.attach_cartridge([chip]) }
      expect(machine.snapshot.load.peek(0x3fff)).to eq(0x5a)
    end

    it "refuses to restore into a machine built another way" do
      expect { described_class.new(model: "620").restore(saved.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /610 with KERNAL 04a at 50 Hz, not a 620/)
    end

    it "refuses an export for VICE" do
      expect { saved.export_snapshot(path) }.to raise_error(Badline::Snapshot::FormatError, /CBM-II/)
    end
  end
end
