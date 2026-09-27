# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

describe Badline::Snapshot do
  include SnapshotScenarios

  # Mid-frame and, at an odd cycle, mid-instruction.
  let(:computer) { run(demo_machine, 30_001) }

  def run_both(first, second, cycles, every: 10_000)
    Array.new(cycles / every) do
      run(first, every)
      run(second, every)
      [Badline::Checkpoint.take(first), Badline::Checkpoint.take(second)]
    end
  end

  describe ".load" do
    before { computer.save_snapshot(snapshot_path) }

    let(:restored) { described_class.load(snapshot_path) }

    it "restores the machine as it was saved" do
      expect(state_differences(computer, restored)).to be_empty
    end

    it "runs on as the saved machine does" do
      run_both(computer, restored, 30_000).each { |ours, theirs| expect(theirs).to eq(ours) }
    end

    it "leaves nothing apart once both have run on" do
      run_both(computer, restored, 20_000)
      expect(Badline::Snapshot::StateWriter.encode(restored)).to eq(Badline::Snapshot::StateWriter.encode(computer))
    end

    it "builds the machine with the snapshot's chip models" do
      demo_machine(vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580).save_snapshot(snapshot_path)
      expect([restored.vic.model, restored.cia1.model, restored.sid.model]).to eq(%i[mos8565 mos6526a mos8580])
    end

    it "leaves the saved machine alone" do
      before = Badline::Snapshot::StateWriter.encode(computer)
      computer.save_snapshot(snapshot_path)
      expect(Badline::Snapshot::StateWriter.encode(computer)).to eq(before)
    end
  end

  describe "#restore_snapshot" do
    let(:target) { run(Badline::Computer.new, 30_000) }

    before { computer.save_snapshot(snapshot_path) }

    it "takes a running machine back to the snapshot" do
      target.restore_snapshot(snapshot_path)
      expect(state_differences(computer, target)).to be_empty
    end

    it "runs on as the saved machine does" do
      target.restore_snapshot(snapshot_path)
      run_both(computer, target, 20_000).each { |ours, theirs| expect(theirs).to eq(ours) }
    end

    it "keeps the target's objects, and the callbacks bound to them" do
      sid = target.sid
      target.restore_snapshot(snapshot_path)
      expect(target.sid).to equal(sid)
    end

    context "when both machines trap CHROUT" do
      before do
        [computer, target].each(&:capture_output)
        computer.capture_output.output << "saved "
        computer.save_snapshot(snapshot_path)
      end

      it "keeps the target's trap, with the snapshot's trap state" do
        target.restore_snapshot(snapshot_path)
        target.cpu.a = 0x41
        target.cpu.instance_variable_get(:@traps).fetch(Badline::ChroutTrap::ADDRESS).call
        expect(target.capture_output.output).to eq("saved a")
      end
    end

    it "leaves the target recording the SID as it was" do
      target.sid.record(rate: 44_100)
      target.restore_snapshot(snapshot_path)
      run(target, 1000)
      expect(target.sid.drain_samples).not_to be_empty
    end

    it "leaves a target that wasn't recording the SID not recording" do
      computer.sid.record(rate: 44_100)
      computer.save_snapshot(snapshot_path)
      target.restore_snapshot(snapshot_path)
      expect(target.sid).not_to be_synthesizing
    end

    it "reports nothing left out" do
      expect(target.restore_snapshot(snapshot_path).ignored).to be_empty
    end
  end

  describe "with a drive mounted" do
    let(:dir) { Dir.mktmpdir }
    let(:computer) do
      File.binwrite(File.join(dir, "demo.prg"), SnapshotScenarios::DEMO_PRG.pack("C*"))
      demo_machine.tap { |machine| machine.mount(Badline::Storage::HostDirectory.new(dir)) }
    end

    before do
      run(computer, 1001)
      computer.save_snapshot(snapshot_path)
    end

    it "mounts it again, with its traps, in a machine without one" do
      expect(state_differences(computer, described_class.load(snapshot_path))).to be_empty
    end

    it "drops a trap the snapshot's machine didn't have" do
      target = Badline::Computer.new
      target.cpu.install_trap(0x1234) { nil }
      target.restore_snapshot(snapshot_path)
      expect(state_differences(computer, target)).to be_empty
    end

    it "loads through the restored drive" do
      restored = described_class.load(snapshot_path)
      drive = restored.instance_variable_get(:@drive)
      expect(drive.instance_variable_get(:@storage).read_file("DEMO")).to eq(SnapshotScenarios::DEMO_PRG)
    end
  end

  describe "with a cartridge" do
    let(:dir) { Dir.mktmpdir }
    # An EasyFlash, whose flash chips call back into the cartridge.
    let(:crt_path) do
      header = "C64 CARTRIDGE   ".b + [0x40, 0x0100, 32, 1, 0].pack("NnnCC") + ("\x00" * 6) + "SNAP".ljust(32, "\x00")
      chips = [0x8000, 0xa000].map do |address|
        "CHIP".b + [0x2010, 2, 0, address, 0x2000].pack("Nn4") + ([address >> 8] * 0x2000).pack("C*")
      end
      File.join(dir, "snap.crt").tap { |path| File.binwrite(path, header + chips.join) }
    end
    let(:computer) do
      Badline::Computer.new.tap { |machine| Badline::Media.attach(machine, crt_path) }
    end

    before do
      run(computer, 20_001)
      computer.save_snapshot(snapshot_path)
    end

    it "builds the same cartridge in a machine without one" do
      restored = described_class.load(snapshot_path)
      expect(state_differences(computer, restored)).to be_empty
    end

    it "wires the new cartridge's parts together" do
      restored = described_class.load(snapshot_path)
      flash = restored.address_bus.cartridge.low_flash
      expect(flash.instance_variable_get(:@on_change)).not_to be_nil
    end

    it "runs on as the saved machine does" do
      restored = described_class.load(snapshot_path)
      run_both(computer, restored, 20_000).each { |ours, theirs| expect(theirs).to eq(ours) }
    end
  end

  describe "with a tape playing" do
    let(:dir) { Dir.mktmpdir }
    let(:computer) do
      pulses = Array.new(4000) { |i| i.even? ? 0x30 : 0x42 }
      path = File.join(dir, "noise.tap")
      File.binwrite(path, "C64-TAPE-RAW".b + [1, 0, 0, 0, pulses.length].pack("C4V") + pulses.pack("C*"))
      demo_machine.tap do |machine|
        machine.datasette.insert(Badline::Storage::TAP.new(path))
        machine.datasette.play!
        machine.address_bus.poke(0, 0x2f)
        machine.address_bus.poke(1, 0x07) # motor on
      end
    end

    it "carries on the tape where it stopped" do
      run(computer, 60_001)
      computer.save_snapshot(snapshot_path)
      restored = described_class.load(snapshot_path)
      run_both(computer, restored, 20_000)
      expect(state_differences(computer, restored)).to be_empty
    end
  end

  describe ".read" do
    it "reads a badline snapshot's modules" do
      computer.save_snapshot(snapshot_path)
      expect(described_class.read(snapshot_path).sections.map(&:name))
        .to eq(%w[MAINCPU C64MEM C64CART CIA1 CIA2 SID SIDEXTENDED FSDRIVE VIC-II GLUE C64MEMHACKS TAPEPORT
                  JOYPORT0 JOYSTICK0 JOYPORT1 JOYSTICK1 USERPORT BADLINE])
    end

    it "knows a snapshot badline wrote" do
      computer.save_snapshot(snapshot_path)
      expect(described_class.read(snapshot_path)).to be_badline
    end
  end
end
