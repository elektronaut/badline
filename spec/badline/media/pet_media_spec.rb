# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Media::PETMedia do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }
  let(:model) { "4032" }

  # A PET that runs what waits for the boot at once.
  let(:pet) do
    Badline::PET.new(model:).tap do |pet|
      allow(pet).to receive(:on_init).and_yield
      allow(pet).to receive(:type_text)
    end
  end

  after { FileUtils.remove_entry(dir) }

  # 10 END, at the start of BASIC.
  def program = [0x01, 0x04, 0x07, 0x04, 0x0a, 0x00, 0x80, 0x00, 0x00, 0x00]

  def write(name, bytes) = File.join(dir, name).tap { |path| File.binwrite(path, bytes.pack("C*")) }

  def word(address) = pet.peek(address) | (pet.peek(address + 1) << 8)

  describe "a program at $0401" do
    before { Badline::Media.attach(pet, write("game.prg", program)) }

    it "goes in at the start of BASIC" do
      expect(Array.new(8) { |i| pet.peek(0x0401 + i) }).to eq(program.drop(2))
    end

    it "ends BASIC's text and LOAD's end address after it" do
      expect([word(0x2a), word(0xc9)]).to eq([0x0409, 0x0409])
    end

    it "runs" do
      expect(pet).to have_received(:type_text).with("run\r")
    end

    context "with BASIC 1" do
      let(:model) { "2001" }

      it "ends BASIC 1's text and LOAD's end address after it" do
        expect([word(0x7c), word(0xe5)]).to eq([0x0409, 0x0409])
      end
    end
  end

  describe "an 8250 disk" do
    let(:disk) { blank_d80(File.join(dir, "game.d82"), sides: 2) }

    before { Badline::Media.attach(pet, disk) }

    it "goes in device 8" do
      expect(pet.mounted_path).to eq(disk)
    end

    it "loads and runs the disk's first program" do
      expect(pet).to have_received(:type_text).with(%(load"*",8\rrun\r))
    end
  end

  describe "a disk on BASIC 1, whose LOAD finds no drive" do
    let(:model) { "2001" }
    let(:disk) { blank_d64(File.join(dir, "game.d64")) }

    before do
      Badline::Storage::D64Image.new(disk).write_file("GAME", program, type: :prg)
      Badline::Media.attach(pet, disk)
    end

    it "mounts it as device 8" do
      expect(pet.mounted_path).to eq(disk)
    end

    it "puts the first program in at the start of BASIC" do
      expect(word(0x7c)).to eq(0x0409)
    end
  end

  describe "a PET tape" do
    let(:message) do
      Badline::Media.attach(pet, Badline::Storage::TAP.create(File.join(dir, "game.tap"), platform: 3).path)
    end

    it "plays on cassette #1" do
      message
      expect(pet.cassettes.datasette1.playing?).to be(true)
    end

    it "loads and runs the tape's first program" do
      message
      expect(pet).to have_received(:type_text).with("load\rrun\r")
    end

    it "says nothing of another machine" do
      expect(message).not_to include("another machine")
    end
  end

  it "mounts a .t64 archive as device 8" do
    entry = [1, 0x82, 0x01, 0x04, 0x03, 0x04, 0, 0, 0x60, 0, 0, 0, 0, 0, 0, 0]
    header = "C64S tape image file".ljust(0x20, "\0").b + [0x0100, 1, 1, 0].pack("vvvv") + "TAPE".ljust(24)
    path = File.join(dir, "tape.t64").tap { |file| File.binwrite(file, header + entry.pack("C*") + "PROG".ljust(16)) }
    Badline::Media.attach(pet, path, autostart: false)
    expect(pet.mounted_path).to eq(path)
  end

  describe "a disk with --true-drive" do
    let(:disk) { blank_d64(File.join(dir, "game.d64")) }

    before do
      Badline::Media::TrueDrive.plug(pet)
      Badline::Media.attach(pet, disk)
    end

    it "goes in the 2031" do
      expect(pet.true_drive.disk.path).to eq(File.expand_path(disk))
    end

    it "leaves the traps unmounted" do
      expect(pet.mounted?).to be(false)
    end

    it "loads and runs the disk's first program" do
      expect(pet).to have_received(:type_text).with(%(load"*",8\rrun\r))
    end

    it "refuses an 8250 disk, which the 2031 doesn't read" do
      path = blank_d80(File.join(dir, "game.d82"), sides: 2)
      expect { Badline::Media.attach(pet, path) }.to raise_error(Badline::Media::TrueDrive::Error, /the 2031 reads/)
    end

    it "refuses a .d81" do
      path = write("game.d81", [0])
      expect { Badline::Media.attach(pet, path) }.to raise_error(Badline::Media::TrueDrive::Error, /the 2031 reads/)
    end
  end

  it "takes a .g64 in a true drive" do
    expect(Badline::Media.kind(pet, write("game.g64", [0]))).to eq(:true_drive)
  end

  %w[game.crt tune.sid].each do |name|
    it "refuses a #{File.extname(name)}" do
      path = write(name, [0])
      expect { Badline::Media.attach(pet, path) }.to raise_error(ArgumentError, /doesn't go in a PET/)
    end
  end
end
