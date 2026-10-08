# frozen_string_literal: true

require "spec_helper"

describe Badline::C128 do
  subject(:machine) { described_class.new }

  def chips(machine)
    [machine.vic.model, machine.cia1.model, machine.sid.model, machine.vdc.model, machine.vdc.ram.length,
     machine.region.name]
  end

  it "is the C128 family" do
    expect(machine.family).to eq(:c128)
  end

  it "starts in C64 mode" do
    expect(machine.mode).to eq(:c64)
  end

  it "starts the 8502 at the C64 KERNAL's reset vector" do
    expect(machine.cpu.program_counter).to eq(0xfce2)
  end

  it "builds the C128 by default" do
    expect(chips(machine)).to eq([:mos8566, :mos6526, :mos6581, :mos8563, 0x4000, :pal])
  end

  it "builds the C128DCR" do
    expect(chips(described_class.new(model: "c128dcr"))).to eq([:mos8566, :mos6526a, :mos8580, :mos8568, 0x10000,
                                                                :pal])
  end

  it "builds the NTSC C128 with the 8564" do
    expect(chips(described_class.new(model: "c128ntsc"))).to eq([:mos8564, :mos6526, :mos6581, :mos8563, 0x4000,
                                                                 :ntsc])
  end

  it "fits the SID given over the model's" do
    expect(described_class.new(model: "c128dcr", sid_model: :mos6581).sid.model).to eq(:mos6581)
  end

  it "refuses a model it can't build" do
    expect { described_class.new(model: "c128d") }.to raise_error(ArgumentError, /c128d/)
  end

  it "deselects every extra keyboard row" do
    expect([machine.vic.extra_keyboard_lines, machine.control_ports.extra_rows]).to eq([0x07, 0xff])
  end

  it "counts its cycles" do
    machine.run_cycles(1234)
    expect([machine.cycles, machine.cpu.cycles]).to eq([1234, 1234])
  end

  it "runs the CPU twice a cycle in FAST mode" do
    machine.address_bus.poke(0xd030, 0x01)
    machine.run_cycles(100)
    expect(machine.cpu.cycles).to eq(200)
  end

  it "runs the CPU once a cycle again when FAST is cleared" do
    machine.address_bus.poke(0xd030, 0x01)
    machine.address_bus.poke(0xd030, 0x00)
    machine.run_cycles(100)
    expect(machine.cpu.cycles).to eq(100)
  end

  it "holds P6 low while CAPS LOCK is down" do
    machine.press_caps_lock
    expect(machine.address_bus.peek(0x01) & 0x40).to eq(0)
  end

  it "lets P6 go high once CAPS LOCK is up" do
    machine.press_caps_lock
    machine.release_caps_lock
    expect(machine.address_bus.peek(0x01) & 0x40).to eq(0x40)
  end

  it "loads a PRG into bank 0" do
    expect([machine.load_prg([0x00, 0xc0, 0x42]), machine.ram.peek(0xc000)]).to eq([0xc000, 0x42])
  end

  it "comes back from a power cycle with the extra keyboard rows deselected" do
    machine.address_bus.poke(0xd02f, 0x00)
    machine.power_cycle!
    expect(machine.control_ports.extra_rows).to eq(0xff)
  end

  it "shows the VIC-IIe as its video" do
    expect(machine.video).to be(machine.vic)
  end

  it "shows the VDC as its :vdc video" do
    expect(machine.video(:vdc)).to be(machine.vdc)
  end

  it "clocks the VDC each cycle" do
    machine.vdc.poke(0xd600, 4)
    machine.vdc.poke(0xd601, 7)
    expect { machine.run_cycles(20_000) }.to change(machine.vdc, :frame)
  end

  it "powers the VDC on again with a power cycle" do
    machine.vdc.ram[0] = 1
    machine.power_cycle!
    expect(machine.vdc.ram[0]).to eq(0)
  end
end
