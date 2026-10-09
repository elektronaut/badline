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

  describe "in FAST mode" do
    # The CPU on the first opcode of +code+ at $2000, with the screen
    # blanked so that no bad line halts it, and FAST set from line 0's
    # first cycle.
    def run_fast(code, cycles)
      machine.ram.write(0x2000, code)
      machine.cpu.step! until machine.cpu.boundary?
      machine.cpu.program_counter = 0x2000
      machine.vic.poke(0xd011, 0x0b)
      machine.address_bus.poke(0xd030, 0x01)
      machine.run_cycles(cycles)
      machine.cpu.cycles
    end

    let(:loop_code) { [0x4c, 0x00, 0x20] }

    it "runs the CPU once in the cycle after the write" do
      expect(run_fast(loop_code, 1)).to eq(1)
    end

    # Pinned by c128/2mhzVIC: each line of its drawing code is 121 CPU
    # cycles long.
    it "runs the CPU in both halves of every cycle but the five refresh cycles" do
      expect(run_fast(loop_code, 1 + (10 * 63)) - 1).to eq(10 * 121)
    end

    # Pinned by c128/2mhzVIC/timing-change0, whose INC $D020 takes 8 half
    # cycles.
    it "lets each I/O access wait for phi2" do
      expect(run_fast([0xee, 0x20, 0xd0], 5)).to eq(6)
    end

    it "runs the CPU once a cycle again from the cycle after FAST is cleared" do
      run_fast(loop_code, 20)
      machine.address_bus.poke(0xd030, 0x00)
      expect { machine.run_cycles(11) }.to change(machine.cpu, :cycles).by(12)
    end
  end

  # Pinned by c128/d030tester's lines cut with the TEST bit on for four
  # cycles and for three.
  it "steps the raster counter in every cycle from the cycle after TEST is set" do
    machine.address_bus.poke(0xd030, 0x02)
    machine.run_cycles(4)
    expect(machine.vic.rasterline).to eq(3)
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

  context "when built for C128 mode" do
    subject(:machine) { described_class.new(mode: :c128) }

    it "starts in C128 mode" do
      expect(machine.mode).to eq(:c128)
    end

    it "starts the 8502 at the C128 KERNAL's reset vector" do
      expect(machine.cpu.program_counter).to eq(machine.address_bus.c128_kernal_rom.peek16(0xfffc))
    end

    it "runs #on_init's handlers once BASIC 7.0 has booted" do
      expect(machine.init_threshold).to eq(2_000_000)
    end

    it "comes back to C128 mode from a reset" do
      machine.address_bus.poke(0xd505, 0xf7)
      machine.reset!
      expect(machine.mode).to eq(:c128)
    end

    it "reads the 40/80 key down through the MMU" do
      machine.press_display_key
      expect(machine.address_bus.peek(0xd505) & 0x80).to eq(0)
    end

    it "reads the 40/80 key up once it is let go" do
      machine.press_display_key
      machine.release_display_key
      expect(machine.address_bus.peek(0xd505) & 0x80).to eq(0x80)
    end

    it "traps the C128 KERNAL's CHROUT" do
      out = machine.capture_output
      machine.run_cycles(machine.init_threshold)
      expect(out.output).to include("ready.")
    end

    it "holds C= until the KERNAL goes to C64 mode" do
      machine.hold_commodore_key
      expect(machine.keyboard.keys).to include(:cbm)
    end

    it "lets C= go once the machine is in C64 mode" do
      machine.hold_commodore_key
      machine.address_bus.poke(0xd505, 0xf7)
      expect(machine.keyboard.keys).not_to include(:cbm)
    end

    it "waits for the C64 KERNAL's boot to run #on_init's handlers after C= takes it to C64 mode" do
      machine.hold_commodore_key
      machine.run_cycles(1000)
      machine.address_bus.poke(0xd505, 0xf7)
      expect(machine.init_threshold).to eq(1000 + Badline::Computer::INIT_THRESHOLD)
    end
  end

  it "refuses a mode it doesn't have" do
    expect { described_class.new(mode: :cpm) }.to raise_error(ArgumentError, /cpm/)
  end
end
