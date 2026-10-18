# frozen_string_literal: true

require "spec_helper"
require "badline/cbm2"

describe Badline::CBM2::IEEEDrive do
  subject(:machine) { Badline::CBM2.new }

  def trap(machine) = machine.instance_variable_get(:@ieee_trap)

  it "plugs a 2031 in as device 8, on the IEEE-488 bus" do
    drive = machine.plug_true_drive
    expect([drive.model_name, machine.true_drive.device, machine.ieee.bus.drives]).to eq(["2031", 8, [drive]])
  end

  it "plugs an 8050 or an 8250 in place of the 2031" do
    machine.plug_true_drive
    drive = machine.plug_drive8050("8250")
    expect([machine.drive2031, machine.true_drive.model_name, machine.ieee.bus.drives]).to eq([nil, "8250", [drive]])
  end

  it "clocks the drive at the machine's 2 MHz" do
    drive = machine.plug_true_drive
    machine.run_cycles(2_000)
    expect(drive.cycles).to eq(1_000)
  end

  it "waits for the drive's boot before typing" do
    machine.plug_drive8050
    expect(machine.init_threshold).to be >= Badline::Drives::Model8050::BOOT_CYCLES
  end

  it "leaves device 8 to the drive, and takes it back once it's gone" do
    machine.mount(Badline::Storage::HostDirectory.new(Dir.pwd))
    machine.plug_true_drive
    leaves = trap(machine).device
    machine.detach_drive2031
    expect([leaves, trap(machine).device]).to eq([nil, 8])
  end

  it "keeps an 8250 in its snapshots" do
    machine.plug_drive8050("8250")
    machine.run_cycles(10_000)
    expect(machine.snapshot.load.true_drive&.model_name).to eq("8250")
  end

  it "keeps a 2031 in its snapshots" do
    machine.plug_true_drive
    machine.run_cycles(10_000)
    expect(machine.snapshot.load.true_drive&.model_name).to eq("2031")
  end
end
