# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../support/taken_once"

describe Badline::CBM2::P500 do
  describe "snapshots" do
    let(:path) { File.join(Dir.mktmpdir, "p500.vsf") }

    # A 510 part way through its KERNAL's reset, into the RAM test, where
    # the indirection register walks the segments, restored from a
    # snapshot taken once.
    def saved
      TakenOnce.fetch(:p500_booting_image) do
        described_class.new.tap { |machine| machine.run_cycles(300_001) }.snapshot
      end.load
    end

    it "restores a machine that runs on as the saved one" do
      machine = saved
      restored = machine.snapshot.load
      [machine, restored].each { |each_machine| each_machine.run_cycles(20_000) }
      expect(restored.snapshot).to eq(machine.snapshot)
    end

    it "saves to a .vsf whose machine is CBM-II-5x0, with badline's modules alone" do
      saved.save_snapshot(path)
      snapshot = Badline::Snapshot.read(path)
      expect([snapshot.container.machine, snapshot.sections.map(&:name)])
        .to eq(["CBM-II-5x0", %w[BL-MACHINE BL-CPU BL-RAM BL-COLORRAM BL-VIC BL-SID BL-CIA BL-ACIA BL-TPI1 BL-TPI2]])
    end

    it "builds the model and mains the snapshot names" do
      machine = described_class.new(model: "510ntsc", mains_hz: 50).snapshot.load
      expect([machine.class, machine.model.name, machine.kernal, machine.mains_hz])
        .to eq([described_class, "510ntsc", "02", 50])
    end

    # TPI1's CA and CB low, and TPI2's PC6 high.
    it "keeps the VIC's view of memory, which the TPIs drive" do
      machine = described_class.new
      { 0xde06 => 0xa1, 0xdf05 => 0xc0, 0xdf02 => 0x40 }.each { |addr, value| machine.poke(addr, value) }
      machine.bus.poke_bank(0, 0x4010, 0x5a)
      expect(machine.snapshot.load.vic.vic_bank.peek(0x0010)).to eq(0x5a)
    end

    it "refuses to restore into a B series machine" do
      expect { Badline::CBM2.new.restore(saved.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /510 with KERNAL 02 at 50 Hz, not a 610/)
    end
  end
end
