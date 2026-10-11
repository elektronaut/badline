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

    # A machine in the middle of its boot, restored from a snapshot taken
    # once for each model and mode.
    def saved(model = "c128", mode: :c64)
      TakenOnce.fetch([:c128_booting_image, model, mode]) { booting(model, mode:).snapshot }.load
    end

    def digest(machine) = [machine.snapshot, Badline::Support::Checkpoint.take(machine).to_s]

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
        restored = machine.snapshot.load
        run_on(machine, restored)
        expect(digest(restored)).to eq(digest(machine))
      end
    end

    it "restores a C128 whose Z80 is booting, which runs on as the saved one" do
      machine = described_class.new(mode: :c128).tap { |booting| booting.run_cycles(301) }
      restored = machine.snapshot.load
      run_on(machine, restored, cycles: 2000)
      expect([restored.z80.inspect, digest(restored)]).to eq([machine.z80.inspect, digest(machine)])
    end

    it "restores a C128 the Z80 has handed to the 8502 as it was" do
      machine = described_class.new(mode: :c128).tap { |booted| booted.run_cycles(2000) }
      expect(machine.snapshot.load.snapshot).to eq(machine.snapshot)
    end

    it "restores a C128 built for C128 mode that runs on as the saved one" do
      machine = booting(mode: :c128)
      restored = machine.snapshot.load
      run_on(machine, restored)
      expect([digest(restored), restored.mode]).to eq([digest(machine), :c128])
    end

    it "carries the MMU's relocation, the P0H write it holds and both colour RAM banks over" do
      machine = saved(mode: :c128)
      write(machine, [[0xd50a, 0x01], [0xd509, 0x30], [0xd508, 0x01], [0x00, 0x03], [0x01, 0x00], [0xd800, 0x05]])
      restored = machine.snapshot.load
      [machine, restored].each { |both| write(both, [[0xd507, 0x40]]) }
      expect(digest(restored)).to eq(digest(machine))
    end

    it "refuses a snapshot of a C128 built for the other mode" do
      image = described_class.new(mode: :c128).snapshot
      expect { described_class.new.restore(image) }.to raise_error(Badline::Snapshot::FormatError, /c128/)
    end

    it "carries FAST mode and the VDC's RAM and registers over" do
      machine = saved("c128dcr")
      write(machine, [[0xd030, 1], [0xd600, 18], [0xd601, 0x12], [0xd600, 31], [0xd601, 42]])
      restored = machine.snapshot.load
      run_on(machine, restored)
      expect([digest(restored), restored.vdc.ram.hash]).to eq([digest(machine), machine.vdc.ram.hash])
    end

    it "carries the TEST bit's raster and display line over, running on as the saved one" do
      machine = saved.tap { |testing| write(testing, [[0xd030, 2]]) }
      machine.run_cycles(30_001)
      restored = machine.snapshot.load
      run_on(machine, restored)
      expect([digest(restored), restored.vic.output_line]).to eq([digest(machine), machine.vic.output_line])
    end

    it "carries the VDC's display size over" do
      machine = saved.tap { |programmed| program_vdc(programmed) }
      machine.run_cycles(40_000)
      restored = machine.snapshot.load
      expect([restored.vdc.width, restored.vdc.height, restored.vdc.crop])
        .to eq([machine.vdc.width, machine.vdc.height, machine.vdc.crop])
    end

    it "carries the disk device 8 serves over" do
      machine = saved
      Badline::Media.attach(machine, blank_d64(File.join(Dir.mktmpdir, "blank.d64")), autostart: false)
      expect(machine.snapshot.load.mounted?).to be(true)
    end

    it "carries a true 1571 over, running on as the saved one" do
      machine = described_class.new.tap { |with_drive| Badline::Media::TrueDrive.plug(with_drive) }
      machine.run_cycles(400_001)
      restored = machine.snapshot.load
      run_on(machine, restored)
      expect([digest(restored), restored.drive1571.nil?]).to eq([digest(machine), false])
    end

    it "carries a true 1541 over, running on as the saved one" do
      machine = described_class.new.tap { |with_drive| with_drive.attach_drive1541(Badline::Drives::Model1541.new) }
      machine.run_cycles(400_001)
      restored = machine.snapshot.load
      run_on(machine, restored)
      expect([digest(restored), restored.drive1541.nil?]).to eq([digest(machine), false])
    end

    it "saves to a .vsf whose machine is C128, with badline's modules alone" do
      saved.save_snapshot(path)
      snapshot = Badline::Snapshot.read(path)
      expect([snapshot.container.machine, snapshot.sections.map(&:name)])
        .to eq(["C128", %w[BL-MACHINE BL-RAM BL-COLORRAM BL-MMU BL-CPU BL-Z80 BL-VIC BL-VDC BL-CIA1 BL-CIA2 BL-SID
                           BL-TAPE]])
    end

    it "loads a C128 from its .vsf, with its model and SID" do
      machine = described_class.new(model: "c128dcrntsc", sid_model: :mos6581).tap { |each| each.run_cycles(1_001) }
      machine.save_snapshot(path)
      loaded = Badline::Snapshot.load(path)
      expect([loaded.class, loaded.model.name, loaded.sid.model, loaded.snapshot])
        .to eq([described_class, "c128dcrntsc", :mos6581, machine.snapshot])
    end

    it "takes a machine back to the snapshot" do
      machine = saved
      image = machine.snapshot
      machine.run_cycles(1_000)
      expect(machine.restore(image).snapshot).to eq(image)
    end

    it "refuses a snapshot of another model" do
      image = described_class.new(model: "c128dcr").snapshot
      expect { described_class.new.restore(image) }.to raise_error(Badline::Snapshot::FormatError, /c128dcr/)
    end

    it "refuses a C64's snapshot" do
      expect { described_class.new.restore(Badline::C64.new.snapshot) }
        .to raise_error(Badline::Snapshot::FormatError, /of a C64, not a C128/)
    end

    context "with C= held from power-on" do
      let(:machine) { described_class.new(mode: :c128).tap(&:hold_commodore_key).tap { |each| each.run_cycles(101) } }
      let(:restored) { machine.snapshot.load }

      it "carries the key held over" do
        expect(restored.keyboard.keys).to eq([:cbm])
      end

      it "lets go once the machine reaches C64 mode, as the saved one does" do
        run_on(machine, restored, cycles: 3_000)
        expect([restored.keyboard.keys, restored.mode, digest(restored)]).to eq([[], :c64, digest(machine)])
      end
    end

    it "refuses a C128 snapshot without badline's modules" do
      File.binwrite(path, Badline::Snapshot::Container.new([], machine: "C128").to_s)
      expect { Badline::Snapshot.load(path) }.to raise_error(Badline::Snapshot::FormatError, /x128/)
    end
  end
end
