# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/snapshot_scenarios"

describe Badline::Snapshot::Vice do
  include SnapshotScenarios

  let(:state) { Badline::Snapshot::MachineState.section(run(demo_machine, 30_001)) }
  # The machine the VICE modules describe: the saved one, run on to the
  # end of its instruction.
  let(:settled) { described_class.settled(state) }
  let(:container) { Badline::Snapshot::Container.new(described_class.export(state)) }
  let(:image) { Badline::Snapshot::Image.new(container) }
  let(:imported) { image.to_computer.tap { |machine| image.restore(machine) { nil } } }

  def cpu_registers(machine)
    cpu = machine.cpu
    [machine.cycles, cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p]
  end

  def cia_registers(cia)
    [cia.timer_a, cia.timer_b, cia.timer_a_latch, cia.timer_b_latch, cia.control_a.value, cia.control_b.value,
     cia.interrupt_control.value, cia.interrupt_status.value, cia.time_of_day.registers,
     *Badline::Snapshot::Vice::CIAs::PORTS.map { |port| cia.instance_variable_get(port) }]
  end

  def voices(machine)
    machine.sid.instance_variable_get(:@voices).map do |voice|
      [voice.waveform.instance_variable_get(:@accumulator), voice.waveform.instance_variable_get(:@shift_register),
       voice.envelope.output, voice.envelope.instance_variable_get(:@state)]
    end
  end

  describe ".export" do
    it "writes the modules x64sc reads, in its order" do
      expect(container.sections.map(&:name))
        .to eq(%w[MAINCPU C64MEM C64CART CIA1 CIA2 SID SIDEXTENDED FSDRIVE VIC-II GLUE C64MEMHACKS TAPEPORT
                  JOYPORT0 JOYSTICK0 JOYPORT1 JOYSTICK1 USERPORT])
    end

    it "writes each module at the size x64sc 3.7 reads" do
      sizes = container.sections.to_h { |section| [section.name, section.data.bytesize] }
      expect(sizes.values_at("MAINCPU", "C64MEM", "CIA1", "SID", "SIDEXTENDED", "VIC-II"))
        .to eq([91, 65_555, 52, 36, 133, 123_415])
    end

    it "describes the machine at an instruction boundary" do
      expect(settled.cpu.instance_variable_get(:@plan)).to equal(Badline::CPU::FETCH_PLAN)
    end
  end

  describe "a machine restored from the VICE modules alone" do
    it "has the CPU's registers and the clock" do
      expect(cpu_registers(imported)).to eq(cpu_registers(settled))
    end

    it "has the RAM and the CPU port" do
      expect([imported.ram.read(0, 0x10000), imported.address_bus.peek(0), imported.address_bus.peek(1)])
        .to eq([settled.ram.read(0, 0x10000), settled.address_bus.peek(0), settled.address_bus.peek(1)])
    end

    it "has both CIAs' registers, timers and clocks" do
      expect([imported.cia1, imported.cia2].map { |cia| cia_registers(cia) })
        .to eq([settled.cia1, settled.cia2].map { |cia| cia_registers(cia) })
    end

    it "has the SID's registers and voices" do
      expect([Array.new(0x19) { |reg| imported.sid.register(reg) }, voices(imported)])
        .to eq([Array.new(0x19) { |reg| settled.sid.register(reg) }, voices(settled)])
    end

    it "has the VIC's registers, beam, colour RAM and counters" do
      vic = ->(machine) { [machine.vic.register_file, machine.vic.rasterline, machine.vic.column] }
      expect(vic.call(imported)).to eq(vic.call(settled))
    end

    it "runs on as the saved machine does, all but the CPU's own cycle count" do
      run(settled, 20_000)
      run(imported, 20_000)
      expect(Badline::Checkpoint.take(imported).differences(Badline::Checkpoint.take(settled))).to eq(["cpu"])
    end

    it "reports the modules badline doesn't read" do
      expect(image.restore(Badline::Computer.new) { nil }.ignored.map { |line| line.split.first })
        .to eq(%w[C64CART FSDRIVE GLUE C64MEMHACKS TAPEPORT JOYPORT0 JOYSTICK0 JOYPORT1 JOYSTICK1 USERPORT])
    end
  end

  describe ".models" do
    it "takes the C64C's chips from an 8565" do
      state = Badline::Snapshot::MachineState.section(Badline::Computer.new(vic_model: :mos8565, sid_model: :mos8580))
      models = described_class.models(Badline::Snapshot::Container.new(described_class.export(state)))
      expect(models).to eq(vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580)
    end
  end

  describe "an unknown module" do
    let(:container) do
      Badline::Snapshot::Container.new(described_class.export(state) +
                                       [Badline::Snapshot::Section.new(name: "REU1764", major: 3, minor: 1, data: "x")])
    end

    it "is reported, not fatal" do
      lines = []
      image.restore(Badline::Computer.new) { |line| lines << line }
      expect(lines).to include("REU1764 3.1: badline doesn't read this module, left out")
    end

    it "is warned without a block" do
      expect { image.restore(Badline::Computer.new) }.to output(/REU1764 3\.1/).to_stderr
    end
  end

  describe "a module cut short" do
    let(:container) do
      short = described_class.export(state).map do |section|
        section.name == "CIA1" ? section.with(data: section.data.byteslice(0, 10)) : section
      end
      Badline::Snapshot::Container.new(short)
    end

    it "fails naming the module" do
      expect { imported }.to raise_error(Badline::Snapshot::FormatError, /CIA1 2\.3 ends early/)
    end
  end
end
