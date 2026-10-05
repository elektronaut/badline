# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/snapshot_scenarios"

# The VICE modules for each model badline builds, the beam position they
# give, and an REU's.
describe Badline::Snapshot::Vice do
  include SnapshotScenarios

  def image(sections) = Badline::Snapshot::Image.new(Badline::Snapshot::Container.new(sections))

  def model_machine(model)
    run(demo_machine(vic_model: model.vic_model, cia_model: model.cia_model, sid_model: model.sid_model,
                     region: model.region), SnapshotScenarios::DEMO_CYCLES)
  end

  # Whether a machine loaded from the VICE modules alone runs on as the
  # copy they were written from does, for a frame and a little more, all
  # but the CPU's own cycle count.
  def runs_on_alike?(state, cycles)
    imported = image(described_class.export(state)).load { nil }
    settled = run(described_class.settled(state), cycles)
    Badline::Checkpoint.take(run(imported, cycles)).differences(Badline::Checkpoint.take(settled)) == ["cpu"]
  end

  # VICE's model number for each model's VIC-II, and the size of the
  # module x64sc 3.10 writes for it.
  {
    "c64" => [0, 123_415], "c64c" => [1, 123_415], "ntsc" => [3, 109_207], "newntsc" => [4, 109_207],
    "oldntsc" => [5, 109_207], "drean" => [6, 123_415]
  }.each do |name, (number, size)|
    describe "the #{name}" do
      let(:model) { Badline::Model.named(name) }
      let(:state) { model_machine(model).snapshot }

      it "writes VICE's VIC-II model #{number}, at the size x64sc 3.10 writes" do
        vic = described_class.export(state).find { |section| section.name == "VIC-II" }
        expect([vic.data.getbyte(0), vic.data.bytesize]).to eq([number, size])
      end

      it "is built again from the VICE modules" do
        container = Badline::Snapshot::Container.new(described_class.export(state))
        expect(Badline::Model.of(described_class.setup(container))).to eq(model)
      end

      it "runs on from the VICE modules alone as the saved machine does" do
        region = model.region
        expect(runs_on_alike?(state, (region.cycles_per_line * region.lines_per_frame) + 1_000)).to be(true)
      end
    end
  end

  # VICE's cycle in the line runs a column ahead of badline's, and its line
  # moves on in its cycle 0, a cycle later at the start of a frame.
  describe "the beam" do
    def at(line, column)
      vic = run(Badline::Computer.new, (line * 63) + column).vic
      vicii = described_class::VICII
      [vicii.vice_cycle(vic), vicii.vice_line(vic), vicii.frame_start?(vic)]
    end

    # A machine running NOPs, stopped between two of them at the beam
    # position, and restored from the VICE modules alone.
    def restored_at(line, column)
      machine = Badline::Computer.new
      machine.ram.write(0x1000, Array.new(0x8000, 0xea))
      machine.cpu.program_counter = 0x1000
      vic = machine.vic
      machine.cycle! until machine.cpu.boundary? && vic.rasterline == line && vic.column == column
      image(described_class.export(machine.snapshot)).load { nil }.vic
    end

    it "is at VICE's cycle in the line less one" do
      expect(at(100, 20)).to eq([21, 100, false])
    end

    it "is at VICE's cycle 0 of the next line in the last column" do
      expect(at(100, 62)).to eq([0, 101, false])
    end

    it "is at VICE's cycle 0 of the last line, starting a frame, in the last column of the frame" do
      expect(at(311, 62)).to eq([0, 311, true])
    end

    [[100, 20], [100, 62], [311, 62], [0, 0]].each do |line, column|
      it "comes back from line #{line}, column #{column}" do
        vic = restored_at(line, column)
        expect([vic.rasterline, vic.column]).to eq([line, column])
      end
    end
  end

  describe "a machine with an REU" do
    # A 512K REU part way through stashing $0400 bytes from $0400 to $2000
    # in bank 3, with the interrupt on the end of the block enabled.
    let(:machine) do
      Badline::Computer.new(reu: 512).tap do |computer|
        bus = computer.address_bus
        { 0xdf02 => 0x00, 0xdf03 => 0x04, 0xdf04 => 0x00, 0xdf05 => 0x20, 0xdf06 => 0x03, 0xdf07 => 0x00,
          0xdf08 => 0x04, 0xdf09 => 0xc0, 0xdf01 => 0x90 }.each { |addr, value| bus.poke(addr, value) }
        run(computer, 101)
      end
    end
    let(:sections) { described_class.export(machine.snapshot) }
    let(:settled) { described_class.settled(machine.snapshot) }

    def reu_state(computer)
      reu = computer.reu
      [reu.size_kb, reu.register_file, reu.ram_contents, reu.irq?]
    end

    it "is saved with the transfer under way" do
      expect(machine.reu).to be_holds_bus
    end

    it "lists the REU in C64CART, followed by REU1764 with its size, registers and RAM" do
      cart, reu = sections.values_at(2, 3)
      expect([cart.data.bytesize, cart.data.byteslice(-4, 4).unpack1("l<"), reu.to_s, reu.data.bytesize])
        .to eq([66, -105, "REU1764 0.0", 4 + 16 + (512 * 1024)])
    end

    it "describes the machine once the transfer has ended, with the IRQ raised" do
      expect([settled.reu.dma?, settled.reu.irq?, settled.cpu.boundary?]).to eq([false, true, true])
    end

    it "comes back from the VICE modules with the REU's size, registers, RAM and IRQ line" do
      expect(reu_state(image(sections).load { nil })).to eq(reu_state(settled))
    end

    it "runs on from the VICE modules alone as the saved machine does" do
      expect(runs_on_alike?(machine.snapshot, 20_000)).to be(true)
    end
  end
end
