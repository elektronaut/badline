# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../support/blank_disk"

describe Badline::KernalTrap::DOS::Writes do
  include BlankDisk

  subject(:drive) { Badline::KernalTrap::DOS.new(Badline::Storage::D64Image.new(path)) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { blank_d64(File.join(dir, "blank.d64")) }

  before { status }

  after { FileUtils.remove_entry(dir) }

  def status
    bytes = []
    loop do
      byte, eoi = drive.read(15)
      bytes << byte
      break if eoi
    end
    bytes.pack("C*").chomp("\r")
  end

  def command(text) = drive.write(15, text.bytes)

  # The image as the host file now holds it
  def disk = Badline::Storage::D64Image.new(path)

  def write_file(secondary, name, bytes)
    drive.open(secondary, name)
    drive.write(secondary, bytes)
    drive.close(secondary)
  end

  describe "an open for writing" do
    before { drive.open(2, "log,s,w") }

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end

    it "listens on the channel" do
      expect(drive.listening?(2)).to be(true)
    end

    it "has nothing to send" do
      expect(drive.read(2)).to be_nil
    end

    it "writes nothing until the channel closes" do
      drive.write(2, [0x41])
      expect(disk.read_file("log", type: nil)).to be_nil
    end
  end

  describe "a file written through a channel" do
    before { write_file(2, "log,s,w", [0x41, 0x42]) }

    it "is on the disk once the channel closes" do
      expect(disk.read_file("log", type: :seq)).to eq([0x41, 0x42])
    end

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end
  end

  describe "the file type an open for writing takes" do
    it "writes a SEQ file on a data channel without a type" do
      write_file(2, "log,w", [0x41])
      expect(disk.read_file("log", type: :seq)).to eq([0x41])
    end

    it "writes a PRG file on SAVE's channel" do
      write_file(1, "0:game", [0x01, 0x08])
      expect(disk.read_file("game")).to eq([0x01, 0x08])
    end

    it "takes the type the name asks for" do
      write_file(2, "data,u,w", [0x41])
      expect(disk.read_file("data", type: :usr)).to eq([0x41])
    end
  end

  describe "an open for writing a name already on the disk" do
    before { write_file(2, "log,s,w", [0x41]) }

    it "reports FILE EXISTS" do
      drive.open(3, "log,p,w")
      expect(status).to eq("63,FILE EXISTS,00,00")
    end

    it "leaves the channel closed" do
      drive.open(3, "log,s,w")
      expect(drive.listening?(3)).to be(false)
    end

    it "writes over it with @" do
      write_file(3, "@0:log,s,w", [0x42])
      expect(disk.read_file("log", type: :seq)).to eq([0x42])
    end
  end

  describe "an open for appending" do
    before do
      write_file(2, "log,s,w", [0x41])
      write_file(2, "log,s,a", [0x42])
    end

    it "adds the bytes to the end of the file" do
      expect(disk.read_file("log", type: :seq)).to eq([0x41, 0x42])
    end

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end

    it "reports FILE NOT FOUND for a missing file" do
      drive.open(2, "gone,s,a")
      expect(status).to eq("62,FILE NOT FOUND,00,00")
    end
  end

  describe "closing the command channel with a file open for writing" do
    before do
      drive.open(2, "log,s,w")
      drive.write(2, [0x41])
      drive.close(15)
    end

    it "loses the file" do
      expect(disk.read_file("log", type: nil)).to be_nil
    end
  end

  describe "a full disk" do
    before { write_file(2, "big,s,w", Array.new(665 * 254, 0)) }

    it "reports DISK FULL" do
      expect(status).to eq("72,DISK FULL,00,00")
    end

    it "leaves the file off the disk" do
      expect(disk.read_file("big", type: nil)).to be_nil
    end
  end

  describe "a SAVE handed over whole" do
    it "writes the file" do
      drive.save("game", [0x01, 0x08, 0x60])
      expect(disk.read_file("game")).to eq([0x01, 0x08, 0x60])
    end

    it "fails a name on the disk as FILE EXISTS" do
      drive.save("game", [0x01, 0x08])
      drive.save("game", [0x01, 0x08])
      expect(status).to eq("63,FILE EXISTS,00,00")
    end

    it "returns false when the disk refuses it" do
      drive.save("game", [0x01, 0x08])
      expect(drive.save("game", [0x01, 0x08])).to be(false)
    end

    it "writes over a name on the disk with replace" do
      drive.save("game", [0x01, 0x08])
      drive.save("game", [0x01, 0x08, 0x60], replace: true)
      expect(disk.read_file("game")).to eq([0x01, 0x08, 0x60])
    end
  end

  describe "a block write" do
    before do
      drive.open(2, "#")
      command("b-p 2 0")
      drive.write(2, [0xde, 0xad])
    end

    it "puts the buffer's block on the disk with U2" do
      command("u2 2 0 1 0")
      expect(disk.read_block(1, 0).first(3)).to eq([0xde, 0xad, 0x00])
    end

    it "reports OK" do
      command("u2 2 0 1 0")
      expect(status).to eq("00, OK,00,00")
    end

    it "stores the count first with B-W" do
      command("b-w 2 0 1 0")
      expect(disk.read_block(1, 0).first(3)).to eq([1, 0xad, 0x00])
    end

    it "leaves the BAM alone" do
      command("u2 2 0 1 0")
      expect(disk.block_free?(1, 0)).to be(true)
    end
  end

  describe "a block allocation" do
    it "marks the block in use" do
      command("b-a 0 1 5")
      expect(disk.block_free?(1, 5)).to be(false)
    end

    it "reports OK" do
      command("b-a 0 1 5")
      expect(status).to eq("00, OK,00,00")
    end

    it "reports NO BLOCK for a block in use, with the next free one" do
      command("b-a 0 1 5")
      command("b-a 0 1 5")
      expect(status).to eq("65,NO BLOCK,01,06")
    end

    it "reports a block the BAM has no entry for" do
      command("b-a 0 36 0")
      expect(status).to eq("66,ILLEGAL TRACK OR SECTOR,36,00")
    end

    it "updates the BAM the drive keeps in its RAM" do
      command("b-a 0 1 0")
      drive.write(15, [*"M-R".bytes, 0x05, 0x07, 1])
      expect(drive.read(15)).to eq([0xfe, true])
    end
  end

  describe "a block free" do
    before do
      command("b-a 0 1 5")
      command("b-f 0 1 5")
    end

    it "marks the block free" do
      expect(disk.block_free?(1, 5)).to be(true)
    end

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end
  end

  describe "the scratch command" do
    before do
      drive.save("game1", [0x01, 0x08])
      drive.save("game2", [0x01, 0x08])
      drive.save("other", [0x01, 0x08])
    end

    it "reports how many files it scratched" do
      command("s0:game*")
      expect(status).to eq("01, FILES SCRATCHED,02,00")
    end

    it "removes them from the disk" do
      command("s:game*")
      expect([disk.read_file("game1"), disk.read_file("other")]).to eq([nil, [0x01, 0x08]])
    end

    it "takes several names" do
      command("s0:game1,0:other\r")
      expect(status).to eq("01, FILES SCRATCHED,02,00")
    end

    it "reports none for a name not on the disk" do
      command("s:gone")
      expect(status).to eq("01, FILES SCRATCHED,00,00")
    end
  end

  describe "a disk that can't be written" do
    subject(:drive) { Badline::KernalTrap::DOS.new(image) }

    let(:image) { Badline::Storage::D64Image.new(path) }

    before { allow(image).to receive(:writable?).and_return(false) }

    it "fails an open for writing" do
      drive.open(2, "log,s,w")
      expect(status).to eq("26,WRITE PROTECT ON,18,00")
    end

    it "fails a scratch" do
      command("s:*")
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
    end

    it "fails a block free" do
      command("b-f 0 1 0")
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
    end

    it "fails a SAVE" do
      drive.save("game", [0x01, 0x08])
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
    end
  end

  describe "a disk image mounted read-only" do
    subject(:drive) { Badline::KernalTrap::DOS.new(Badline::Storage::D64Image.new(path, read_only: true)) }

    let(:path) do
      blank_d64(File.join(dir, "blank.d64")).tap do |blank|
        Badline::Storage::D64Image.new(blank).write_file("game", [0x01, 0x08, 0x60])
      end
    end
    let!(:original) { File.binread(path) }

    before { drive.open(3, "#") }

    {
      "an open for writing" => [-> { drive.open(2, "log,s,w") }, "26,WRITE PROTECT ON,18,00"],
      "a SAVE's channel" => [-> { drive.open(1, "new") }, "26,WRITE PROTECT ON,18,01"],
      "an append" => [-> { drive.open(2, "game,p,a") }, "26,WRITE PROTECT ON,17,00"],
      "a SAVE handed over whole" => [-> { drive.save("new", [0x01, 0x08]) }, "26,WRITE PROTECT ON,00,00"],
      "a replacing SAVE" => [-> { drive.save("game", [0x01, 0x08], replace: true) }, "26,WRITE PROTECT ON,00,00"],
      "a scratch" => [-> { command("s:game") }, "26,WRITE PROTECT ON,00,00"],
      "a U2 block write" => [-> { command("u2 3 0 1 0") }, "26,WRITE PROTECT ON,01,00"],
      "a B-W block write" => [-> { command("b-w 3 0 1 0") }, "26,WRITE PROTECT ON,01,00"],
      "a B-A" => [-> { command("b-a 0 1 0") }, "26,WRITE PROTECT ON,00,00"],
      "a B-F" => [-> { command("b-f 0 1 0") }, "26,WRITE PROTECT ON,00,00"]
    }.each do |write, (action, message)|
      context "with #{write}" do
        before { instance_exec(&action) }

        it "fails as WRITE PROTECT ON" do
          expect(status).to eq(message)
        end

        it "leaves the image file as it was" do
          expect(File.binread(path)).to eq(original)
        end
      end
    end

    it "still reads files" do
      drive.open(0, "game")
      expect(drive.read(0)).to eq([0x01, false])
    end
  end

  describe "a disk change" do
    let(:other) { blank_d64(File.join(dir, "other.d64")) }

    before do
      Badline::Storage::D64Image.new(other).write_file("second", [0x01, 0x08, 0x02])
      drive.open(2, "log,s,w")
      drive.insert(Badline::Storage::D64Image.new(other))
    end

    it "reads the new disk" do
      drive.open(0, "second")
      expect(drive.read(0)).to eq([0x01, false])
    end

    it "closes the channels" do
      expect(drive.listening?(2)).to be(false)
    end

    it "reads the new disk's BAM into its RAM" do
      drive.write(15, [*"M-R".bytes, 0x00, 0x07, 3])
      expect(Array.new(3) { drive.read(15).first }).to eq([18, 1, 0x41])
    end

    it "writes to the new disk" do
      drive.save("game", [0x01, 0x08])
      expect(Badline::Storage::D64Image.new(other).read_file("game")).to eq([0x01, 0x08])
    end
  end
end
