# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../support/xpet_snapshots"

describe Badline::Snapshot::Vice::PET::Drive2031 do
  include XpetSnapshots

  def image(container) = Badline::Snapshot::Image.new(container)

  # An 8032 with a 2031 a few cycles on, between instructions, its drive
  # RAM marked and its head moved off track 18.
  def with_drive
    pet = Badline::PET.new
    drive = pet.plug_true_drive
    XpetSnapshots.to_boundary(XpetSnapshots.run(pet, 40))
    XpetSnapshots.set_up_crtc(pet, XpetSnapshots::CRTC80)
    drive.ram.write(0x0300, [0x12, 0x34, 0x56])
    drive.instance_variable_get(:@mechanism).send(:seek, 32)
    pet
  end

  def exported(pet = with_drive) = XpetSnapshots.exported(pet)

  def section_bytes(container) = container.sections.to_h { |section| [section.to_s, section.data.bytesize] }

  def drive_cpu(pet)
    cpu = pet.true_drive.instance_variable_get(:@cpu)
    [cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p]
  end

  def half_track(pet) = pet.true_drive.instance_variable_get(:@mechanism).half_track

  describe "the modules written for a PET with a 2031" do
    it "follow the VIA in xpet's order" do
      expect(exported.sections.map(&:name))
        .to eq(%w[MAINCPU CPU6809 PETMEM CRTC PIA1 PIA2 VIA DRIVE8 DRIVE9 DRIVE10 DRIVE11 DRIVECPU0 VIA2D0
                  2031VIA1D0 FSDRIVE TAPEPORT USERPORT])
    end

    it "have the versions and sizes xpet 3.10 writes" do
      expect(section_bytes(exported).slice("DRIVE8 2.0", "DRIVECPU0 1.3", "VIA2D0 2.2", "2031VIA1D0 2.2"))
        .to eq("DRIVE8 2.0" => 145, "DRIVECPU0 1.3" => 2152, "VIA2D0 2.2" => 28, "2031VIA1D0 2.2" => 28)
    end

    it "put the drive's RAM after DRIVECPU0's registers" do
      expect(exported["DRIVECPU0"].data.byteslice(0x5c + 0x300, 3).bytes).to eq([0x12, 0x34, 0x56])
    end

    it "put the head's half track in DRIVE8" do
      expect(exported["DRIVE8"].data.getbyte(0x10)).to eq(32)
    end

    it "are taken with the drive's CPU between instructions as well as the PET's" do
      pet = with_drive
      pet.cycle! until !pet.true_drive.cpu.boundary? && pet.cpu.boundary?
      Badline::Snapshot::Image.exported(pet)
      expect([pet.cpu.boundary?, pet.true_drive.cpu.boundary?]).to eq([true, true])
    end
  end

  describe "a PET with a 2031 restored from xpet's modules" do
    subject(:restored) do
      Badline::PET.new.tap { |pet| image(exported(saved)).restore(pet) { nil } }
    end

    let(:saved) { with_drive }

    it "puts a 2031 on the bus" do
      expect(restored.true_drive&.model_name).to eq("2031")
    end

    it "has the drive's registers" do
      expect(drive_cpu(restored)).to eq(drive_cpu(saved))
    end

    it "has the drive's RAM" do
      expect(restored.true_drive.ram.read(0x0300, 3)).to eq([0x12, 0x34, 0x56])
    end

    it "has the head where it was" do
      expect(half_track(restored)).to eq(32)
    end
  end

  it "takes the 2031 off the bus for a snapshot without one, and says so" do
    lines = []
    pet = Badline::PET.new.tap(&:plug_true_drive)
    saved = XpetSnapshots.to_boundary(Badline::PET.new).tap { |pet| XpetSnapshots.set_up_crtc(pet, XpetSnapshots::CRTC80) }
    image(XpetSnapshots.exported(saved)).restore(pet) { |line| lines << line }
    expect([pet.true_drive, lines.last]).to eq([nil, "the 2031 on device 8 is taken off the bus"])
  end
end
