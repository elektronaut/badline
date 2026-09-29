# frozen_string_literal: true

require "spec_helper"

describe Badline::Drive1541::Idle do
  # The C64's side of the bus: CIA 2's port A lines, which the spec sets.
  let(:host) { Struct.new(:port_a_lines).new(0x07) }
  # INC $10; DEC $10; JMP $EBFF
  let(:pure_loop) { [0xe6, 0x10, 0xc6, 0x10, 0x4c, 0xff, 0xeb] }

  # LDA #$FF; STA $1C02; LDA #$00; STA $1C00: VIA 2's port B driven, with
  # the motor off.
  def motor_off = [0xa9, 0xff, 0x8d, 0x02, 0x1c, 0xa9, 0x00, 0x8d, 0x00, 0x1c]

  # A drive whose ROM holds +loop+ at $EBFF, and +init+ at $E000, where
  # the reset vector points, after turning the motor off and followed by a
  # jump to $EBFF.
  def drive_running(loop, init: [], idle_skip: true)
    bytes = Array.new(0x4000, 0xea)
    bytes[0x2000, motor_off.length + init.length + 3] = [*motor_off, *init, 0x4c, 0xff, 0xeb]
    bytes[0x2bff, loop.length] = loop
    bytes[0x3ffc, 2] = [0x00, 0xe0]
    rom = Badline::ROM.new(bytes, length: 0x4000, start: 0xc000)
    Badline::Drive1541.new(rom:).tap do |drive|
      drive.idle_skip = idle_skip
      drive.connect(Badline::IECBus.new(host:))
    end
  end

  # How many of +cycles+ host cycles the drive spent asleep.
  def asleep_for(drive, cycles)
    Array.new(cycles) do
      drive.host_cycle!
      drive.asleep?
    end.count(true)
  end

  def state(drive) = self.class.state(drive)

  # Everything the drive holds.
  def self.state(drive)
    cpu = drive.cpu
    vias = [drive.via1, drive.via2].flat_map { |via| [*via.idle_state, via.timer1, via.timer2, via.port_b_output] }
    [drive.cycles, cpu.cycles, cpu.instructions, *cpu.idle_state, *vias, *drive.mechanism.idle_state,
     drive.ram.read(0, 0x0800)]
  end

  it "sleeps through a loop that puts back what it changes" do
    expect(asleep_for(drive_running(pure_loop), 10_000)).to be > 9_900
  end

  {
    "changes RAM for good" => [0xe6, 0x10, 0x4c, 0xff, 0xeb], # INC $10; JMP $EBFF
    "reads a counter" => [0xad, 0x04, 0x18, 0x4c, 0xff, 0xeb], # LDA $1804; JMP $EBFF
    "reads the serial bus" => [0xad, 0x00, 0x18, 0x4c, 0xff, 0xeb], # LDA $1800; JMP $EBFF
    "writes VIA 1" => [0x8d, 0x01, 0x18, 0x4c, 0xff, 0xeb], # STA $1801; JMP $EBFF
    "writes a timer" => [0x8d, 0x06, 0x1c, 0x4c, 0xff, 0xeb], # STA $1C06; JMP $EBFF
    # LDA #$04; STA $1C00; LDA #$00; STA $1C00; JMP $EBFF
    "turns the motor on" => [0xa9, 0x04, 0x8d, 0x00, 0x1c, 0xa9, 0x00, 0x8d, 0x00, 0x1c, 0x4c, 0xff, 0xeb]
  }.each do |what, loop|
    it "stays awake through a loop that #{what}" do
      expect(asleep_for(drive_running(loop), 2_000)).to eq(0)
    end
  end

  it "stays awake with idle_skip off" do
    expect(asleep_for(drive_running(pure_loop, idle_skip: false), 2_000)).to eq(0)
  end

  it "stays awake while the CPU has a trap to run" do
    drive = drive_running(pure_loop)
    drive.cpu.install_trap(0xec00) { nil }
    expect(asleep_for(drive, 2_000)).to eq(0)
  end

  it "runs every cycle for a CPU that logs each instruction" do
    expect(Badline::Drive1541.new(debug: true).idle_skip).to be(false)
  end

  it "wakes when ATN moves" do
    drive = drive_running(pure_loop)
    asleep_for(drive, 100)
    host.port_a_lines = 0x0f
    drive.host_cycle!
    expect(drive.asleep?).to be(false)
  end

  it "sleeps through CLK and DATA moving" do
    drive = drive_running(pure_loop)
    asleep_for(drive, 100)
    host.port_a_lines = 0x37
    drive.host_cycle!
    expect(drive.asleep?).to be(true)
  end

  it "wakes to be read" do
    drive = drive_running(pure_loop)
    asleep_for(drive, 100)
    drive.cpu
    expect(drive.asleep?).to be(false)
  end

  it "wakes before its counters set a flag" do
    # LDA #$C0; STA $1C0E; LDA #$00; STA $1C04; LDA #$04; STA $1C05; CLI:
    # VIA 2's timer 1 interrupts $0402 cycles on.
    drive = drive_running(pure_loop, init: [0xa9, 0xc0, 0x8d, 0x0e, 0x1c, 0xa9, 0x00, 0x8d, 0x04, 0x1c,
                                            0xa9, 0x04, 0x8d, 0x05, 0x1c, 0x58])
    asleep_for(drive, 100)
    expect(asleep_for(drive, 0x0400)).to be < 0x0400
  end

  # Each drive's state after each stretch of host cycles.
  def states(drives, stretches)
    stretches.map do |cycles|
      cycles.times { drives.each(&:host_cycle!) }
      drives.map { |drive| state(drive) }
    end
  end

  it "leaves the drive as running every cycle does" do
    drives = [drive_running(pure_loop), drive_running(pure_loop, idle_skip: false)]
    expect(states(drives, [1, 7, 100, 1000, 0x2345])).to all(satisfy { |skipping, stepping| skipping == stepping })
  end

  it "leaves the head where running every cycle does, through zone changes over a blank track" do
    # Init: LDA #$04; STA $1C00; LDX #$00; DEX; BNE *-1; LDA #$00; STA $1C00, the motor turning a
    # while. Loop: LDA #$60; STA $1C00; LDA #$00; STA $1C00; JMP $EBFF, zone 3 and back.
    init = [0xa9, 0x04, 0x8d, 0x00, 0x1c, 0xa2, 0x00, 0xca, 0xd0, 0xfd, 0xa9, 0x00, 0x8d, 0x00, 0x1c]
    loop = [0xa9, 0x60, 0x8d, 0x00, 0x1c, 0xa9, 0x00, 0x8d, 0x00, 0x1c, 0x4c, 0xff, 0xeb]
    drives = [drive_running(loop, init:), drive_running(loop, init:, idle_skip: false)]
    expect(states(drives, [3000, 100, 1000])).to all(satisfy { |skipping, stepping| skipping == stepping })
  end

  it "reads the LED without waking" do
    drive = drive_running(pure_loop)
    asleep_for(drive, 100)
    drive.led_on?
    expect(drive.asleep?).to be(true)
  end
end
