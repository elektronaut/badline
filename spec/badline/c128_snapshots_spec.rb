# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/blank_disk"
require_relative "../support/taken_once"

describe Badline::C128 do
  include BlankDisk

  describe "snapshots" do
    let(:path) { File.join(Dir.mktmpdir, "c128.vsf") }

    # A machine run to the middle of its boot.
    def booting(model = "c128", mode: :c64)
      described_class.new(model:, mode:).tap { |machine| machine.run_cycles(400_001) }
    end

    # A machine in the middle of its boot, restored from a State taken once
    # for each model and mode.
    def saved(model = "c128", mode: :c64)
      described_class.restored(TakenOnce.fetch([:c128_booting, model, mode]) { booting(model, mode:).snapshot })
    end

    def digest(machine) = [machine.snapshot, Badline::Checkpoint.take(machine).to_s]

    def run_on(*machines, cycles: 60_000) = machines.each { |machine| machine.run_cycles(cycles) }

    def write(machine, pokes) = pokes.each { |addr, value| machine.address_bus.poke(addr, value) }

    # The VDC's registers set for 127 characters a line and 39 rows of 8
    # lines.
    def program_vdc(machine)
      write(machine, [[0xd600, 0], [0xd601, 126], [0xd600, 4], [0xd601, 38], [0xd600, 9], [0xd601, 7]])
    end

    described_class::Model::ALL.each do |model|
      it "restores a #{model.name} that runs on as the saved one" do
        machine = booting(model.name)
        restored = described_class.restored(machine.snapshot)
        run_on(machine, restored)
        expect(digest(restored)).to eq(digest(machine))
      end
    end

    it "restores a C128 whose Z80 is booting, which runs on as the saved one" do
      machine = described_class.new(mode: :c128).tap { |booting| booting.run_cycles(301) }
      restored = described_class.restored(machine.snapshot)
      run_on(machine, restored, cycles: 2000)
      expect([restored.z80.inspect, digest(restored)]).to eq([machine.z80.inspect, digest(machine)])
    end

    it "restores a C128 the Z80 has handed to the 8502 as it was" do
      machine = described_class.new(mode: :c128).tap { |booted| booted.run_cycles(2000) }
      expect(described_class.restored(machine.snapshot).snapshot).to eq(machine.snapshot)
    end

    it "restores a C128 built for C128 mode that runs on as the saved one" do
      machine = booting(mode: :c128)
      restored = described_class.restored(machine.snapshot)
      run_on(machine, restored)
      expect([digest(restored), restored.mode]).to eq([digest(machine), :c128])
    end

    it "carries the MMU's relocation, the P0H write it holds and both colour RAM banks over" do
      machine = saved(mode: :c128)
      write(machine, [[0xd50a, 0x01], [0xd509, 0x30], [0xd508, 0x01], [0x00, 0x03], [0x01, 0x00], [0xd800, 0x05]])
      restored = described_class.restored(machine.snapshot)
      [machine, restored].each { |both| write(both, [[0xd507, 0x40]]) }
      expect(digest(restored)).to eq(digest(machine))
    end

    it "refuses a state of a C128 built for the other mode" do
      state = described_class.new(mode: :c128).snapshot
      expect { described_class.new.restore(state) }.to raise_error(Badline::Snapshot::FormatError, /c128/)
    end

    it "carries FAST mode and the VDC's RAM and registers over" do
      machine = saved("c128dcr")
      write(machine, [[0xd030, 1], [0xd600, 18], [0xd601, 0x12], [0xd600, 31], [0xd601, 42]])
      restored = described_class.restored(machine.snapshot)
      run_on(machine, restored)
      expect([digest(restored), restored.vdc.ram.hash]).to eq([digest(machine), machine.vdc.ram.hash])
    end

    it "carries the TEST bit's raster and display line over, running on as the saved one" do
      machine = saved.tap { |testing| write(testing, [[0xd030, 2]]) }
      machine.run_cycles(30_001)
      restored = described_class.restored(machine.snapshot)
      run_on(machine, restored)
      expect([digest(restored), restored.vic.output_line]).to eq([digest(machine), machine.vic.output_line])
    end

    it "carries the VDC's display size over" do
      machine = saved.tap { |programmed| program_vdc(programmed) }
      machine.run_cycles(40_000)
      restored = described_class.restored(machine.snapshot)
      expect([restored.vdc.width, restored.vdc.height, restored.vdc.crop])
        .to eq([machine.vdc.width, machine.vdc.height, machine.vdc.crop])
    end

    it "carries the disk device 8 serves over" do
      machine = saved
      Badline::Media.attach(machine, blank_d64(File.join(Dir.mktmpdir, "blank.d64")), autostart: false)
      expect(described_class.restored(machine.snapshot).mounted?).to be(true)
    end

    it "carries a true 1571 over, running on as the saved one" do
      machine = described_class.new.tap { |with_drive| Badline::Media::TrueDrive.plug(with_drive) }
      machine.run_cycles(400_001)
      restored = described_class.restored(machine.snapshot)
      run_on(machine, restored)
      expect([digest(restored), restored.drive1571.nil?]).to eq([digest(machine), false])
    end

    it "carries a true 1541 over, running on as the saved one" do
      machine = described_class.new.tap { |with_drive| with_drive.attach_drive1541(Badline::Drive1541.new) }
      machine.run_cycles(400_001)
      restored = described_class.restored(machine.snapshot)
      run_on(machine, restored)
      expect([digest(restored), restored.drive1541.nil?]).to eq([digest(machine), false])
    end

    it "saves to a .vsf whose machine is C128, with the BADLINE module alone" do
      saved.save_snapshot(path)
      expect(Badline::Snapshot.read(path).sections.map(&:name)).to eq(["BADLINE"])
    end

    it "loads a C128 from its .vsf, with its model and SID" do
      machine = described_class.new(model: "c128dcrntsc", sid_model: :mos6581).tap { |each| each.run_cycles(1_001) }
      machine.save_snapshot(path)
      loaded = Badline::Snapshot.load(path)
      expect([loaded.class, loaded.model.name, loaded.sid.model, loaded.snapshot])
        .to eq([described_class, "c128dcrntsc", :mos6581, machine.snapshot])
    end

    it "takes a machine back to the state" do
      machine = saved
      state = machine.snapshot
      machine.run_cycles(1_000)
      expect(machine.restore(state).snapshot).to eq(state)
    end

    it "refuses a state of another model" do
      state = described_class.new(model: "c128dcr").snapshot
      expect { described_class.new.restore(state) }.to raise_error(Badline::Snapshot::FormatError, /c128dcr/)
    end

    it "refuses a C64's state" do
      expect { described_class.new.restore(Badline::Computer.new.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /expected C128/)
    end

    it "refuses a C128 snapshot without the BADLINE module" do
      File.binwrite(path, Badline::Snapshot::Container.new([], machine: "C128").to_s)
      expect { Badline::Snapshot.load(path) }.to raise_error(Badline::Snapshot::FormatError, /x128/)
    end
  end
end
