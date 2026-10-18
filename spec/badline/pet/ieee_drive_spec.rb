# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../support/pet_boot"
require_relative "../../support/blank_disk"

describe Badline::PET::IEEEDrive do
  include PETBoot
  include BlankDisk

  subject(:pet) { Badline::PET.new(model: "4032", ram_kb: 4) }

  # 10 PRINT"HI"
  def hello = [0x01, 0x04, 0x0b, 0x04, 0x0a, 0x00, 0x99, 0x22, 0x48, 0x49, 0x22, 0x00, 0x00, 0x00]

  # The names a directory listing shows on its screen.
  def listed(screen) = screen.grep(/PRG/).map { |line| line.split[1] }

  # A PET with 4K and a 2031 holding a disk with HELLO, that types each of
  # +lines+ and runs on until the screen ends in READY. again. Returns the
  # screen after each line, and what the disk holds as SAVED at the end.
  def session_once(model, lines)
    TakenOnce.fetch([:pet_2031_session, model, lines]) do
      Dir.mktmpdir do |dir|
        path = blank_d64(File.join(dir, "blank.d64"), id: "XY")
        Badline::Storage::D64Image.new(path).write_file("HELLO", hello, type: :prg)
        pet = Badline::PET.new(model:, ram_kb: 4)
        pet.plug_true_drive.insert_image(path)
        pet.run_cycles(pet.init_threshold)
        screens = lines.map { |line| type_line(pet, line) }
        pet.true_drive.flush
        [screens, Badline::Storage::D64Image.new(path).read_file("saved")]
      end
    end
  end

  # Types +line+ and runs until the screen's last line says READY.
  def type_line(pet, line)
    pet.type_text("#{line}\r")
    200.times do
      pet.run_cycles(50_000)
      break if screen_of(pet, 25).reject(&:empty?).last == "READY."
    end
    screen_of(pet, 25).reject(&:empty?)
  end

  it "plugs a 2031 in as device 8" do
    expect([pet.plug_true_drive.model_name, pet.true_drive.device]).to eq(["2031", 8])
  end

  it "puts it on the PET's IEEE-488 bus" do
    drive = pet.plug_true_drive
    expect(pet.ieee.bus.drives).to eq([drive])
  end

  it "takes it off the bus again" do
    drive = pet.plug_true_drive
    pet.detach_drive2031
    expect([pet.true_drive, pet.ieee.bus.drives.include?(drive)]).to eq([nil, false])
  end

  it "waits for the drive's boot before typing" do
    pet.plug_true_drive
    expect(pet.init_threshold).to eq(Badline::Drives::Model2031::BOOT_CYCLES)
  end

  describe "with the traps" do
    def trap(pet) = pet.instance_variable_get(:@ieee_trap)

    before { pet.mount(Badline::Storage::HostDirectory.new(Dir.pwd)) }

    it "leaves device 8 to a 2031 plugged in" do
      pet.plug_true_drive
      expect(trap(pet).device).to be_nil
    end

    it "serves device 8 again once it is gone" do
      pet.plug_true_drive
      pet.detach_drive2031
      expect(trap(pet).device).to eq(8)
    end

    it "leaves device 8 to a 2031 mounted after it" do
      pet.unmount
      pet.plug_true_drive
      pet.mount(Badline::Storage::HostDirectory.new(Dir.pwd))
      expect(trap(pet).device).to be_nil
    end
  end

  describe "BASIC 4", :slow do
    let(:session) do
      session_once("4032", ['dload"hello"', "list", 'dsave"saved"', "directory",
                            "1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d:end\rrun", 'load"hello",9'])
    end
    let(:screens) { session.first }

    it "loads a program with DLOAD" do
      expect(screens[1].last(2)).to eq([' 10 PRINT"HI"', "READY."])
    end

    it "saves it with DSAVE" do
      expect(session.last).to eq(hello)
    end

    it "lists the disk with DIRECTORY" do
      expect(listed(screens[3])).to eq(['"HELLO"', '"SAVED"'])
    end

    it "reads the error channel" do
      expect(screens[4].last(2)).to eq([" 0 OK 0  0", "READY."])
    end

    # The 2031 answers every command under ATN, as xpet's does, so the
    # KERNAL finds a device and no file.
    it "finds no file on device 9" do
      expect(screens[5].last(2)).to eq(["?FILE NOT FOUND ERROR", "READY."])
    end
  end

  describe "BASIC 2", :slow do
    let(:screens) { session_once("3032", ['load"hello",8', "list", 'load"$",8', "list"]).first }

    it "loads a program with LOAD" do
      expect(screens[1].last(2)).to eq([' 10 PRINT"HI"', "READY."])
    end

    it "loads the directory" do
      expect(listed(screens[3])).to eq(['"HELLO"'])
    end
  end

  describe "BASIC 1", :slow do
    let(:session) { session_once("2001", ["1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d:end\rrun"]) }

    it "reads the drive's power-on message from the error channel" do
      expect(session.first[0].last(2)).to eq([" 73 CBM DOS V2.6 2031 0  0", "READY."])
    end
  end

  it "resets the drive with the PET" do
    drive = pet.plug_true_drive
    allow(drive).to receive(:reset!)
    pet.reset!
    expect(drive).to have_received(:reset!)
  end
end
