# frozen_string_literal: true

require "spec_helper"

describe Badline::KernalTrap::Drive do
  subject(:drive) { described_class.new(storage) }

  let(:storage) do
    instance_double(Badline::Storage::D64Image,
                    read_file: [0x01, 0x08, 0x2a],
                    read_block: Array.new(256) { |i| i },
                    block_error: nil,
                    read_error: nil)
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
    it "reports the DOS version at power-on" do
      expect(status).to eq("73,CBM DOS V2.6 1541,00,00")
    end

    it "reports OK once the power-on message has been read" do
      status
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

    %w[u3 u8 uc uh u< u@ up].each do |user_code|
      it "reports OK for #{user_code}, as if the drive code returned" do
        command(user_code)
        expect(status).to eq("00, OK,00,00")
      end
    end

    it "accepts U0" do
      command("u0")
      expect(status).to eq("00, OK,00,00")
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

    it "takes a PRG on the LOAD secondary address" do
      drive.open(0, "program")
      expect(storage).to have_received(:read_file).with("program", type: :prg)
    end

    it "lets the type field override the LOAD secondary address" do
      drive.open(0, "scores,s")
      expect(storage).to have_received(:read_file).with("scores", type: :seq)
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

  describe "a file whose chain runs into a bad block" do
    before do
      allow(storage).to receive_messages(read_file: Array.new(300, 0x11),
                                         read_error: { error: 23, track: 17, sector: 10, offset: 254 })
      drive.open(2, "data")
    end

    it "reports OK when it opens" do
      expect(status).to eq("00, OK,00,00")
    end

    it "holds back the last byte before the bad block" do
      expect(read_channel(2).length).to eq(253)
    end

    it "flags no EOI on the last byte it sends" do
      252.times { drive.read(2) }
      expect(drive.read(2)).to eq([0x11, false])
    end

    it "reports the block's error once the bytes run out" do
      read_channel(2)
      expect(status).to eq("23,READ ERROR,17,10")
    end
  end

  describe "a file whose first block is bad" do
    before do
      allow(storage).to receive(:read_error).and_return({ error: 21, track: 17, sector: 0, offset: 0 })
      drive.open(0, "data")
    end

    it "reports the block's error when it opens" do
      expect(status).to eq("21,READ ERROR,17,00")
    end

    it "leaves the channel empty" do
      expect(drive.read(0)).to be_nil
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

    %w[ua uq].each do |alias_command|
      it "decodes #{alias_command} as U1" do
        command("#{alias_command} 2 0 17 3")
        expect(storage).to have_received(:read_block).with(17, 3)
      end
    end
  end

  describe "a block the error table marks bad" do
    before do
      allow(storage).to receive(:block_error).with(18, 18).and_return(23)
      drive.open(2, "#")
      command("u1:2 0 18 18")
    end

    it "reports the read error with its track and sector" do
      expect(status).to eq("23,READ ERROR,18,18")
    end

    it "still fills the buffer" do
      expect(read_channel(2)).to eq((0..255).to_a)
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

  describe "a block write" do
    before { drive.open(2, "#") }

    %w[u2 ub ur b-w].each do |block_write|
      it "fails #{block_write} at the block it names" do
        command("#{block_write}:2,0,18,1")
        expect(status).to eq("26,WRITE PROTECT ON,18,01")
      end
    end

    it "reports NO CHANNEL without an open buffer" do
      command("u2 3 0 18 1")
      expect(status).to eq("70,NO CHANNEL,00,00")
    end

    it "reports a block outside the image" do
      allow(storage).to receive(:read_block).and_return(nil)
      command("u2 2 0 36 0")
      expect(status).to eq("66,ILLEGAL TRACK OR SECTOR,36,00")
    end
  end

  describe "a block write on storage without block access" do
    let(:storage) { instance_double(Badline::Storage::T64) }

    before do
      drive.open(2, "#")
      command("u2 2 0 18 1")
    end

    it "reports DRIVE NOT READY" do
      expect(status).to eq("74,DRIVE NOT READY,00,00")
    end
  end

  describe "a block allocation" do
    before { command("b-a 0 18 1") }

    it "reports WRITE PROTECT ON" do
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
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

  describe "writing to a channel that isn't open" do
    before do
      command("i0")
      drive.write(2, [0xaa])
    end

    it "leaves the status alone" do
      expect(status).to eq("00, OK,00,00")
    end

    it "isn't listening" do
      expect(drive.listening?(2)).to be(false)
    end
  end

  describe "an open for writing on a write-protected disk" do
    before do
      allow(storage).to receive_messages(read_file: nil, new_entry_block: [18, 4], header_block: [18, 0])
    end

    it "fails SAVE's channel at the new directory entry's block" do
      drive.open(1, "game")
      expect(status).to eq("26,WRITE PROTECT ON,18,04")
    end

    it "fails a W mode open at the header block" do
      drive.open(2, "log,s,w")
      expect(status).to eq("26,WRITE PROTECT ON,18,00")
    end

    it "leaves the channel closed" do
      drive.open(2, "log,s,w")
      expect(drive.listening?(2)).to be(false)
    end

    it "reports FILE EXISTS for a name on the disk, of any type" do
      allow(storage).to receive(:read_file).with("log", type: nil).and_return([0x41])
      drive.open(2, "log,s,w")
      expect(status).to eq("63,FILE EXISTS,00,00")
    end

    it "fails a replace with WRITE PROTECT ON" do
      allow(storage).to receive(:read_file).and_return([0x41])
      drive.open(1, "@0:game")
      expect(status).to eq("26,WRITE PROTECT ON,18,04")
    end
  end

  describe "an open for writing on storage without blocks" do
    let(:storage) { instance_double(Badline::Storage::T64, read_file: nil) }

    it "reports WRITE PROTECT ON without a block" do
      drive.open(1, "game")
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

  describe "a reset command" do
    def memory_at(address)
      drive.write(15, [*"M-R".bytes, address & 0xff, address >> 8, 1])
      read_channel(15).first
    end

    before do
      drive.open(2, "#")
      drive.write(15, [*"M-W".bytes, 0x00, 0x05, 1, 0xaa])
    end

    %w[uj u: uz ui u9 uy u; uk u\[ UJ].each do |reset|
      it "reports the DOS version after #{reset}" do
        command(reset)
        expect(status).to eq("73,CBM DOS V2.6 1541,00,00")
      end

      it "closes the open channels on #{reset}" do
        command(reset)
        expect(drive.read(2)).to be_nil
      end
    end

    it "takes a reset passed as the open filename" do
      drive.open(15, "u;")
      expect(status).to eq("73,CBM DOS V2.6 1541,00,00")
    end

    it "clears the drive's memory through the reset vector" do
      command("u:")
      expect(memory_at(0x500)).to eq(0)
    end

    it "keeps the drive's memory through the NMI vector" do
      command("ui")
      expect(memory_at(0x500)).to eq(0xaa)
    end

    it "keeps the drive's memory through the IRQ vector" do
      command("u;")
      expect(memory_at(0x500)).to eq(0xaa)
    end

    %w[ui+ uy+ u9-].each do |speed|
      it "only switches the bus speed with #{speed}" do
        command(speed)
        expect(status).to eq("00, OK,00,00")
      end
    end

    it "keeps the channels open on UI-" do
      command("ui-")
      expect(drive.read(2)).not_to be_nil
    end
  end

  describe "drive memory" do
    def memory_command(*bytes)
      drive.write(15, bytes)
    end

    it "reads back what M-W wrote" do
      memory_command(*"M-W".bytes, 0x00, 0x05, 3, 0xc1, 0x0d, 0x42)
      memory_command(*"M-R".bytes, 0x00, 0x05, 3)
      expect(read_channel(15)).to eq([0xc1, 0x0d, 0x42])
    end

    it "reads one byte without a count" do
      memory_command(*"M-R".bytes, 0x00, 0x05, 0x0d)
      expect(read_channel(15)).to eq([0x00])
    end

    it "reports OK after the bytes read" do
      memory_command(*"M-R".bytes, 0x00, 0x05)
      read_channel(15)
      expect(status).to eq("00, OK,00,00")
    end

    it "takes a command passed as the open filename" do
      drive.open(15, "M-R\x00\x05\x02".b)
      expect(read_channel(15)).to eq([0x00, 0x00])
    end
  end

  describe "a read job" do
    def run_job(track, sector)
      drive.write(15, [*"M-W".bytes, 0x06, 0x00, 2, track, sector])
      drive.write(15, [*"M-W".bytes, 0x00, 0x00, 1, 0x80])
      drive.write(15, [*"M-R".bytes, 0x00, 0x00, 1])
      read_channel(15).first
    end

    it "reads the block into the job's buffer" do
      run_job(18, 0)
      drive.write(15, [*"M-R".bytes, 0x10, 0x03, 2])
      expect(read_channel(15)).to eq([0x10, 0x11])
    end

    it "reports success" do
      expect(run_job(18, 0)).to eq(1)
    end

    it "reports the error table's code for a bad block" do
      allow(storage).to receive(:block_error).with(2, 1).and_return(21)
      expect(run_job(2, 1)).to eq(3)
    end

    it "reports a missing header for a block outside the image" do
      allow(storage).to receive(:read_block).and_return(nil)
      expect(run_job(99, 0)).to eq(2)
    end
  end
end
