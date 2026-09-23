# frozen_string_literal: true

require "spec_helper"

describe Badline::KernalTrap::Drive do
  subject(:drive) { described_class.new(storage) }

  let(:storage) do
    instance_double(Badline::Storage::D64Image,
                    read_file: [0x01, 0x08, 0x2a],
                    read_block: Array.new(256) { |i| i })
  end

  def read_channel(secondary)
    bytes = []
    loop do
      byte, eoi = drive.read(secondary)
      break unless byte

      bytes << byte
      break if eoi
    end
    bytes
  end

  def status
    read_channel(15).pack("C*").chomp("\r")
  end

  def command(text)
    drive.write(15, text.bytes)
  end

  describe "the command channel" do
    it "reports OK before anything happens" do
      expect(status).to eq("00, OK,00,00")
    end

    it "clears the error once the message has been read" do
      command("nonsense")
      status
      expect(status).to eq("00, OK,00,00")
    end

    it "rejects an unknown command" do
      command("nonsense")
      expect(status).to eq("30,SYNTAX ERROR,00,00")
    end

    it "accepts initialize" do
      command("i0")
      expect(status).to eq("00, OK,00,00")
    end

    it "rejects a block write" do
      command("u2 2 0 18 0")
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
    end

    it "takes a command passed as the open filename" do
      drive.open(15, "nonsense")
      expect(status).to eq("30,SYNTAX ERROR,00,00")
    end
  end

  describe "a file channel" do
    before { drive.open(2, "0:data,p,r") }

    it "looks the name up without the drive prefix, by its type" do
      expect(storage).to have_received(:read_file).with("data", type: :prg)
    end

    it "hands out the file bytes" do
      expect(read_channel(2)).to eq([0x01, 0x08, 0x2a])
    end

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end
  end

  describe "the file type an open asks for" do
    it "reads a SEQ file" do
      drive.open(2, "scores,s,r")
      expect(storage).to have_received(:read_file).with("scores", type: :seq)
    end

    it "reads a USR file" do
      drive.open(2, "notes,u")
      expect(storage).to have_received(:read_file).with("notes", type: :usr)
    end

    it "takes any type without a type field" do
      drive.open(2, "anything")
      expect(storage).to have_received(:read_file).with("anything", type: nil)
    end

    it "takes only a PRG on the LOAD secondary address" do
      drive.open(0, "program,s")
      expect(storage).to have_received(:read_file).with("program", type: :prg)
    end
  end

  describe "a missing file" do
    before do
      allow(storage).to receive(:read_file).and_return(nil)
      drive.open(2, "nope")
    end

    it "reports FILE NOT FOUND" do
      expect(status).to eq("62,FILE NOT FOUND,00,00")
    end

    it "leaves the channel empty" do
      expect(drive.read(2)).to be_nil
    end
  end

  describe "a block read" do
    before do
      drive.open(2, "#")
      command("u1 2 0 18 1")
    end

    it "reports OK" do
      expect(status).to eq("00, OK,00,00")
    end

    it "reads the requested block" do
      expect(storage).to have_received(:read_block).with(18, 1)
    end

    it "fills the buffer channel" do
      expect(read_channel(2)).to eq((0..255).to_a)
    end

    it "accepts the colon-separated form" do
      command("u1:2,0,17,0")
      expect(status).to eq("00, OK,00,00")
    end

    it "moves the buffer pointer" do
      command("b-p 2 253")
      expect(read_channel(2)).to eq([253, 254, 255])
    end
  end

  describe "an old-style block read" do
    before do
      allow(storage).to receive(:read_block).and_return([3, 10, 20, 30, 40, 50])
      drive.open(5, "#")
      command("b-r:5,0,2,15\r")
    end

    it "reads the requested block" do
      expect(storage).to have_received(:read_block).with(2, 15)
    end

    it "hands out the bytes its first byte counts" do
      expect(read_channel(5)).to eq([10, 20, 30])
    end
  end

  describe "a block read without an open buffer" do
    before { command("u1 2 0 18 1") }

    it "reports NO CHANNEL" do
      expect(status).to eq("70,NO CHANNEL,00,00")
    end
  end

  describe "a block read outside the image" do
    before do
      allow(storage).to receive(:read_block).and_return(nil)
      drive.open(2, "#")
      command("u1 2 0 99 3")
    end

    it "reports the offending track and sector" do
      expect(status).to eq("66,ILLEGAL TRACK OR SECTOR,99,03")
    end
  end

  describe "a storage backend without block access" do
    let(:storage) { instance_double(Badline::Storage::T64, read_file: nil) }

    before do
      drive.open(2, "#")
      command("u1 2 0 18 1")
    end

    it "reports DRIVE NOT READY" do
      expect(status).to eq("74,DRIVE NOT READY,00,00")
    end
  end

  describe "writing to a data channel" do
    before do
      drive.open(2, "#")
      drive.write(2, [0xaa])
    end

    it "reports WRITE PROTECT ON" do
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
    end
  end

  describe "closing channels" do
    before { drive.open(2, "#") }

    it "drops the channel" do
      drive.close(2)
      expect(drive.read(2)).to be_nil
    end

    it "drops every channel when the command channel closes" do
      drive.close(15)
      expect(drive.read(2)).to be_nil
    end
  end
end
