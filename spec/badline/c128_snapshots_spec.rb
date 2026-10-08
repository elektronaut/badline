# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/blank_disk"

describe Badline::C128 do
  include BlankDisk

  describe "snapshots" do
    let(:path) { File.join(Dir.mktmpdir, "c128.vsf") }

    # A machine run to the middle of its boot.
    def saved(model = "c128") = described_class.new(model:).tap { |machine| machine.run_cycles(400_001) }

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
        machine = saved(model.name)
        restored = described_class.restored(machine.snapshot)
        run_on(machine, restored)
        expect(digest(restored)).to eq(digest(machine))
      end
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

    it "carries a true 1541 over, running on as the saved one" do
      machine = described_class.new.tap { |with_drive| Badline::Media::TrueDrive.plug(with_drive) }
      machine.run_cycles(400_001)
      restored = described_class.restored(machine.snapshot)
      run_on(machine, restored)
      expect(digest(restored)).to eq(digest(machine))
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
      expect { saved.restore(saved("c128dcr").snapshot) }.to raise_error(Badline::Snapshot::FormatError, /c128dcr/)
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
