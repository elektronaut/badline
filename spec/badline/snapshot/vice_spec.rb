# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/snapshot_scenarios"

describe Badline::Snapshot::Vice do
  include SnapshotScenarios

  let(:state) { SnapshotScenarios.demo_state }
  # The machine the VICE modules describe: the saved one, run on to the
  # end of its instruction.
  let(:settled) { described_class.settled(state) }
  let(:container) { Badline::Snapshot::Container.new(described_class.export(state)) }
  let(:image) { Badline::Snapshot::Image.new(container) }
  let(:imported) { image.load { nil } }

  def cpu_registers(machine)
    cpu = machine.cpu
    [machine.cycles, cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p]
  end

  def cia_registers(cia)
    [cia.timer_a, cia.timer_b, cia.timer_a_latch, cia.timer_b_latch, cia.control_a.value, cia.control_b.value,
     cia.interrupt_control.value, cia.interrupt_status.value, cia.time_of_day.registers, cia.port_registers]
  end

  def voices(machine)
    machine.sid.voices.map { |voice| voice.waveform.resid_fields + voice.envelope.resid_fields }
  end

  def without_log_levels(data) = data.byteslice(0, 19) + data.byteslice(31..)

  def with_section(name)
    sections = described_class.export(state).map { |section| section.name == name ? yield(section) : section }
    Badline::Snapshot::Image.new(Badline::Snapshot::Container.new(sections))
  end

  describe ".export" do
    it "writes the modules x64sc reads, in its order" do
      expect(container.sections.map(&:name))
        .to eq(%w[MAINCPU C64MEM C64CART CIA1 CIA2 SID SIDEXTENDED FSDRIVE VIC-II GLUE C64MEMHACKS TAPEPORT
                  JOYPORT0 JOYSTICK0 JOYPORT1 JOYSTICK1 USERPORT])
    end

    it "writes each module at the version and size x64sc 3.10 reads" do
      sizes = container.sections.to_h { |section| [section.to_s, section.data.bytesize] }
      expect(sizes.values_at("MAINCPU 1.4", "C64MEM 0.1", "CIA1 2.3", "SID 1.5", "SIDEXTENDED 1.4", "VIC-II 1.3"))
        .to eq([103, 65_555, 52, 36, 133, 123_415])
    end

    it "describes the machine at an instruction boundary" do
      expect(settled.cpu).to be_boundary
    end
  end

  describe "a machine restored from the VICE modules alone" do
    it "has the CPU's registers and the clock" do
      expect(cpu_registers(imported)).to eq(cpu_registers(settled))
    end

    it "has the RAM and the CPU port" do
      expect([imported.ram.read(0, 0x10000), imported.address_bus.port_state])
        .to eq([settled.ram.read(0, 0x10000), settled.address_bus.port_state])
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

    it "runs on as the saved machine does, all but the CPU's own cycle count, once a frame is drawn" do
      run(settled, 20_000)
      run(imported, 20_000)
      expect(Badline::Checkpoint.take(imported).differences(Badline::Checkpoint.take(settled))).to eq(["cpu"])
    end

    it "reports the modules badline doesn't read" do
      expect(image.restore(Badline::Computer.new) { nil }.ignored.map { |line| line.split.first })
        .to eq(%w[C64CART FSDRIVE GLUE C64MEMHACKS TAPEPORT JOYPORT0 JOYSTICK0 JOYPORT1 JOYSTICK1 USERPORT])
    end
  end

  describe "restored into a running machine" do
    # Mid-instruction at an odd cycle, with a cartridge in.
    subject(:target) do
      Badline::Computer.new.tap do |machine|
        machine.attach_cartridge(Badline::Cartridge::GeoRAM.new(size: 64))
        run(machine, 3_017)
      end
    end

    before { image.restore(target) { nil } }

    it "runs on as a new machine restored from it does" do
      run(target, 10_000)
      run(imported, 10_000)
      expect(Badline::Checkpoint.take(target)).to eq(Badline::Checkpoint.take(imported))
    end

    it "takes the cartridge out, as VICE saw the port empty" do
      expect(target.address_bus.cartridge).to be_nil
    end
  end

  describe "a snapshot that fails to restore into a running machine" do
    # Mid-instruction at an odd cycle, with a cartridge in.
    def running_machine
      Badline::Computer.new.tap do |machine|
        machine.attach_cartridge(Badline::Cartridge::GeoRAM.new(size: 64))
        run(machine, 3_017)
      end
    end

    # The VIC-II module cut short, which only its import finds.
    def restore_short(machine)
      with_section("VIC-II") { |section| section.with(data: section.data.byteslice(0, 10)) }.restore(machine)
    rescue Badline::Snapshot::FormatError
      machine
    end

    it "leaves the machine as it was" do
      machine = running_machine
      saved = machine.snapshot
      expect(restore_short(machine).snapshot).to eq(saved)
    end

    it "leaves the cartridge in" do
      expect(restore_short(running_machine).address_bus.cartridge).to be_a(Badline::Cartridge::GeoRAM)
    end
  end

  describe "a C64C's snapshot" do
    def c64c
      machine = Badline::Computer.new(vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580)
      Badline::Snapshot::Image.new(Badline::Snapshot::Container.new(described_class.export(machine.snapshot)))
    end

    it "loads into a C64C" do
      restored = c64c.load { nil }
      expect([restored.vic.model, restored.cia1.model, restored.sid.model]).to eq(%i[mos8565 mos6526a mos8580])
    end

    it "fails to restore into a machine built another way" do
      expect { c64c.restore(Badline::Computer.new) }
        .to raise_error(Badline::Snapshot::FormatError, /c64c, mos8565, mos6526a, mos8580, pal, not c64, mos6569/)
    end
  end

  describe ".setup" do
    it "takes the C64C's chips from an 8565" do
      machine = Badline::Computer.new(vic_model: :mos8565, sid_model: :mos8580)
      setup = described_class.setup(Badline::Snapshot::Container.new(described_class.export(machine.snapshot)))
      expect([setup.vic_model, setup.cia_model, setup.sid_model]).to eq(%i[mos8565 mos6526a mos8580])
    end

    it "refuses a VIC-II model VICE added after the 6572" do
      newer = with_section("VIC-II") { |section| section.with(data: "\x07".b + section.data.byteslice(1..)) }
      expect { newer.load }.to raise_error(Badline::Snapshot::FormatError, /model 7, which badline doesn't build/)
    end

    it "builds no REU for an REU1764 version it doesn't know" do
      reu = Badline::Snapshot::Section.new(name: "REU1764", major: 1, minor: 0, data: [512].pack("V"))
      container = Badline::Snapshot::Container.new(described_class.export(state) + [reu])
      expect(described_class.setup(container).reu).to be_nil
    end

    it "refuses an REU of a size badline doesn't build" do
      reu = Badline::Snapshot::Section.new(name: "REU1764", major: 0, minor: 0, data: [96].pack("V"))
      container = Badline::Snapshot::Container.new(described_class.export(state) + [reu])
      expect { described_class.setup(container) }.to raise_error(Badline::Snapshot::FormatError, /a 96K REU/)
    end
  end

  describe "module versions" do
    # 1.2 lacks the ANE and LXA log levels and the jammed flag.
    it "reads MAINCPU 1.2, as VICE 3.7 writes it" do
      old = with_section("MAINCPU") { |section| section.with(minor: 2, data: without_log_levels(section.data)) }
      restored = old.load { nil }
      expect(cpu_registers(restored)).to eq(cpu_registers(settled))
    end

    it "reads MAINC64CPU 1.5, as VICE's development versions name it" do
      trunk = with_section("MAINCPU") { |section| section.with(name: "MAINC64CPU", minor: 5) }
      restored = trunk.load { nil }
      expect(cpu_registers(restored)).to eq(cpu_registers(settled))
    end

    it "reads VIC-IISC 1.4, as VICE's development versions name it" do
      trunk = with_section("VIC-II") { |section| section.with(name: "VIC-IISC", minor: 4) }
      restored = trunk.load { nil }
      expect([restored.vic.register_file, restored.vic.rasterline]).to eq([settled.vic.register_file,
                                                                           settled.vic.rasterline])
    end

    it "fails on a MAINCPU version it doesn't know" do
      newer = with_section("MAINCPU") { |section| section.with(minor: 9) }
      expect { newer.restore(Badline::Computer.new) }
        .to raise_error(Badline::Snapshot::FormatError, /MAINCPU 1\.9: badline doesn't read this version/)
    end

    it "leaves out and reports another module's version it doesn't know" do
      lines = []
      with_section("VIC-II") { |section| section.with(minor: 9) }.restore(Badline::Computer.new) { |line| lines << line }
      expect(lines).to include("VIC-II 1.9: badline doesn't read this version, left out")
    end
  end

  describe "an unknown module" do
    let(:container) do
      Badline::Snapshot::Container.new(described_class.export(state) +
                                       [Badline::Snapshot::Section.new(name: "GEORAM", major: 3, minor: 1, data: "x")])
    end

    it "is reported, not fatal" do
      lines = []
      image.restore(Badline::Computer.new) { |line| lines << line }
      expect(lines).to include("GEORAM 3.1: badline doesn't read this module, left out")
    end

    it "is warned without a block" do
      expect { image.restore(Badline::Computer.new) }.to output(/GEORAM 3\.1/).to_stderr
    end
  end

  it "fails naming a module cut short" do
    short = with_section("CIA1") { |section| section.with(data: section.data.byteslice(0, 10)) }
    expect { short.restore(Badline::Computer.new) }
      .to raise_error(Badline::Snapshot::FormatError, /CIA1 2\.3 ends early/)
  end
end
