# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/snapshot_scenarios"

describe Badline::Snapshot do
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

  describe "with a tape whose file is gone" do
    before do
      tape = File.join(Dir.mktmpdir, "gone.tap")
      File.binwrite(tape, "C64-TAPE-RAW".b + [1, 0, 0, 0, 1].pack("C4V") + "\x30".b)
      computer.datasette.insert(Badline::Storage::TAP.new(tape))
      computer.save_snapshot(path)
      File.delete(tape)
    end

    it "fails to load" do
      expect { described_class.load(path) }.to raise_error(Badline::Snapshot::FormatError, /won't open/)
    end
  end

  it "fails on a file that isn't a snapshot" do
    File.binwrite(path, "not a snapshot")
    expect { described_class.load(path) }.to raise_error(Badline::Snapshot::FormatError, /not a VICE snapshot/)
  end
end
