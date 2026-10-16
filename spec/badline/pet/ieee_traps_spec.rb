# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../support/pet_boot"
require_relative "../../support/blank_disk"

describe Badline::PET::IEEETraps do
  include PETBoot
  include BlankDisk

  # 10 PRINT"HI"
  def hello = [0x01, 0x04, 0x0b, 0x04, 0x0a, 0x00, 0x99, 0x22, 0x48, 0x49, 0x22, 0x00, 0x00, 0x00]

  # The names a directory listing shows on its screen.
  def listed(screen) = screen.grep(/PRG/).map { |line| line.split[1] }

  # A PET with 4K, booted with a host directory holding HELLO as device 8,
  # or with +d64+ a disk holding it, that types each of +lines+ and runs on for
  # +cycles+ after each. Returns the screen after each line, and the
  # directory's files at the end.
  def session_once(model, lines, cycles: 300_000, d64: false)
    TakenOnce.fetch([:pet_ieee_session, model, lines]) do
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, "HELLO.PRG"), hello.pack("C*"))
        pet = Badline::PET.new(model:, ram_kb: 4)
        storage = d64 ? Badline::Storage::D64Image.new(blank_d64(File.join(dir, "blank.d64"))) : nil
        storage&.write_file("HELLO", hello, type: :prg)
        pet.mount(storage || Badline::Storage::HostDirectory.new(dir))
        pet.run_cycles(pet.init_threshold)
        screens = lines.map do |line|
          pet.type_text("#{line}\r")
          pet.run_cycles(cycles)
          screen_of(pet, 25).reject(&:empty?)
        end
        [screens, Dir.children(dir).sort.to_h { |name| [name, File.binread(File.join(dir, name)).bytes] }]
      end
    end
  end

  describe "BASIC 4", :slow do
    let(:session) do
      session_once("4032", ['load"hello",8', "list", 'save"saved",8', "directory", 'dload"saved"', "list",
                            'load"hello",9'])
    end
    let(:screens) { session.first }

    it "loads a program with LOAD" do
      expect(screens[1].last(2)).to eq([' 10 PRINT"HI"', "READY."])
    end

    it "saves it with SAVE" do
      expect(session.last["saved.prg"]).to eq(hello)
    end

    it "lists the disk with DIRECTORY" do
      expect(listed(screens[3])).to eq(['"HELLO"', '"SAVED"'])
    end

    it "loads a program with DLOAD" do
      expect(screens[5].last(2)).to eq([' 10 PRINT"HI"', "READY."])
    end

    it "finds no device 9" do
      expect(screens[6].last(2)).to eq(["?DEVICE NOT PRESENT ERROR", "READY."])
    end
  end

  describe "BASIC 2", :slow do
    let(:session) { session_once("3032", ['load"hello",8', "list", 'save"saved",8', 'load"$",8', "list"]) }
    let(:screens) { session.first }

    it "loads a program with LOAD" do
      expect(screens[1].last(2)).to eq([' 10 PRINT"HI"', "READY."])
    end

    it "saves it with SAVE" do
      expect(session.last["saved.prg"]).to eq(hello)
    end

    it "loads the directory" do
      expect(listed(screens[4])).to eq(['"HELLO"', '"SAVED"'])
    end
  end

  # BASIC 1's UNLISTEN leaves its command in FA, so the TALK its LOAD
  # sends after opening the file goes to no device, and nothing loads.
  # OPEN, PRINT#, INPUT# and CLOSE take FA from the file table.
  describe "BASIC 1", :slow do
    let(:session) do
      session_once("2001", ['10 open2,8,2,"data,s,w":print#2,"x7":close2', '20 open2,8,2,"data":input#2,a$:close2:?a$',
                            "run", "new", 'load"hello",8', "list"], d64: true)
    end
    let(:screens) { session.first }

    it "writes and reads a sequential file" do
      expect(screens[2].last(2)).to eq(%w[X7 READY.])
    end

    it "loads nothing with LOAD" do
      expect(screens[5].last(2)).to eq(%w[LIST READY.])
    end
  end
end
