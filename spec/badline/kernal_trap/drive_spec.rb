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

  describe "a carriage return in a file name" do
    # The 1541's CMDSET ($C2B3) shortens the name before OPEN looks it up.
    it "drops one that ends the name" do
      drive.open(0, "s2\r")
      expect(storage).to have_received(:read_file).with("s2", type: :prg)
    end

    it "drops one before the last byte, with that byte" do
      drive.open(0, "s2\rx")
      expect(storage).to have_received(:read_file).with("s2", type: :prg)
    end

    it "keeps one further in" do
      drive.open(2, "a\rbc")
      expect(storage).to have_received(:read_file).with("a\rbc", type: nil)
    end

    it "keeps a name that is only a carriage return" do
      drive.open(2, "\r")
      expect(storage).to have_received(:read_file).with("\r", type: nil)
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

    it "reads a control character as a parameter of 0" do
      command("u1:2,0,18,\x02\r")
      expect(storage).to have_received(:read_block).with(18, 0)
    end

    it "reads the characters past 9 up to ? as digits 10 to 15" do
      command("u1:2,0,1:,?")
      expect(storage).to have_received(:read_block).with(20, 15)
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

  describe "writing to a buffer channel" do
    def buffer_at(position, count = 1)
      command("b-p 2 #{position}")
      Array.new(count) { drive.read(2).first }
    end

    before do
      drive.open(2, "#")
      command("b-p 2 1")
      drive.write(2, [0x41, 0x42, 0x43])
    end

    it "leaves the status alone" do
      expect(status).to eq("00, OK,00,00")
    end

    it "fills the buffer from the pointer" do
      expect(buffer_at(0, 4)).to eq([0x00, 0x41, 0x42, 0x43])
    end

    it "wraps the pointer within the block" do
      command("b-p 2 255")
      drive.write(2, [0x0d, 0x0e])
      expect(buffer_at(0)).to eq([0x0e])
    end

    it "stores the index of the last byte written on B-W" do
      command("b-w 2 0 18 1")
      expect(buffer_at(0)).to eq([3])
    end

    it "stores 1 on B-W when nothing has been written" do
      command("b-p 2 0")
      command("b-w 2 0 18 1")
      expect(buffer_at(0)).to eq([1])
    end

    it "leaves the pointer at 1 after B-W" do
      command("b-w 2 0 18 1")
      expect(drive.read(2)).to eq([0x41, false])
    end

    it "keeps the block as it is on U2" do
      command("u2 2 0 18 1")
      expect(buffer_at(0)).to eq([0x00])
    end

    it "keeps the image's block out of it" do
      command("u1 2 0 18 1")
      drive.write(2, [0xff])
      expect(storage.read_block(18, 1).first).to eq(0)
    end
  end

  describe "writing to a file channel" do
    before do
      drive.open(2, "data")
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

  describe "an open for appending on a write-protected disk" do
    before do
      allow(storage).to receive_messages(read_file: [0x41], last_block: [17, 3])
      drive.open(2, "log,s,a")
    end

    it "fails at the file's last block" do
      expect(status).to eq("26,WRITE PROTECT ON,17,03")
    end

    it "looks the file up by its type" do
      expect(storage).to have_received(:last_block).with("log", type: :seq)
    end

    it "leaves the channel closed" do
      expect(drive.listening?(2)).to be(false)
    end
  end

  describe "an open for appending to a missing file" do
    before do
      allow(storage).to receive(:read_file).and_return(nil)
      drive.open(2, "log,a")
    end

    it "reports FILE NOT FOUND" do
      expect(status).to eq("62,FILE NOT FOUND,00,00")
    end
  end

  describe "an open for writing on storage without blocks" do
    let(:storage) { instance_double(Badline::Storage::T64, read_file: nil) }

    it "reports WRITE PROTECT ON without a block" do
      drive.open(1, "game")
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
    end

    it "fails an append without a block" do
      allow(storage).to receive(:read_file).and_return([0x41])
      drive.open(2, "log,a")
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
    end
  end

  describe "a SAVE handed over whole" do
    let(:storage) { instance_double(Badline::Storage::HostDirectory, write_file: true) }

    it "writes the file" do
      drive.save("game", [0x01, 0x08])
      expect(storage).to have_received(:write_file).with("game", [0x01, 0x08])
    end

    it "reports OK" do
      drive.save("game", [0x01, 0x08])
      expect(status).to eq("00, OK,00,00")
    end

    it "reports WRITE PROTECT ON when the host refuses the write" do
      allow(storage).to receive(:write_file).and_return(false)
      drive.save("game", [0x01, 0x08])
      expect(status).to eq("26,WRITE PROTECT ON,00,00")
    end

    it "returns whether the file was written" do
      allow(storage).to receive(:write_file).and_return(false)
      expect(drive.save("game", [0x01, 0x08])).to be(false)
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

  describe "buffer allocation" do
    def buffer_of(secondary)
      command("b-p #{secondary} 0")
      drive.write(secondary, [secondary])
      (0...4).find { |number| memory_at(0x300 + (number * 0x100)) == secondary }
    end

    def memory_at(address)
      drive.write(15, [*"M-R".bytes, address & 0xff, address >> 8, 1])
      read_channel(15).first
    end

    it "gives the first buffer channel buffer 3, as the BAM holds buffer 4" do
      drive.open(2, "#")
      expect(buffer_of(2)).to eq(3)
    end

    it "hands out the highest free buffer" do
      (2..5).each { |secondary| drive.open(secondary, "#") }
      expect((2..5).map { |secondary| buffer_of(secondary) }).to eq([3, 2, 1, 0])
    end

    it "reports NO CHANNEL once the four free buffers are taken" do
      (2..6).each { |secondary| drive.open(secondary, "#") }
      expect(status).to eq("70,NO CHANNEL,00,00")
    end

    it "leaves the channel closed when no buffer is free" do
      (2..6).each { |secondary| drive.open(secondary, "#") }
      expect(drive.listening?(6)).to be(false)
    end

    it "counts a buffer for an open file" do
      drive.open(2, "data")
      drive.open(3, "#")
      expect(buffer_of(3)).to eq(2)
    end

    it "reports NO CHANNEL for a file once the buffers are taken" do
      (2..5).each { |secondary| drive.open(secondary, "#") }
      drive.open(6, "data")
      expect(status).to eq("70,NO CHANNEL,00,00")
    end

    it "frees the buffer when the channel closes" do
      drive.open(2, "#")
      drive.close(2)
      drive.open(3, "#")
      expect(buffer_of(3)).to eq(3)
    end

    it "frees a channel's buffer when its secondary address opens again" do
      drive.open(2, "#")
      drive.open(2, "#")
      expect(buffer_of(2)).to eq(3)
    end

    it "takes the buffer a name asks for" do
      drive.open(2, "#1")
      expect(buffer_of(2)).to eq(1)
    end

    [["the BAM's buffer", "#4"], ["a buffer past the fifth", "#5"]].each do |what, name|
      it "reports NO CHANNEL for #{what}" do
        drive.open(2, name)
        expect(status).to eq("70,NO CHANNEL,00,00")
      end
    end

    it "keeps a channel open when the buffer it asks for again is taken" do
      drive.open(2, "#3")
      drive.open(2, "#3")
      expect(buffer_of(2)).to eq(3)
    end
  end

  describe "a buffer channel in drive RAM" do
    def memory_command(*bytes)
      drive.write(15, bytes)
    end

    before { drive.open(2, "#") }

    it "shows M-R what PRINT# wrote, from the second byte on" do
      drive.write(2, [0x41, 0x42])
      memory_command(*"M-R".bytes, 0x00, 0x06, 3)
      expect(read_channel(15)).to eq([0x00, 0x41, 0x42])
    end

    it "answers the first read with the buffer's number" do
      expect(drive.read(2)).to eq([3, false])
    end

    it "moves on to the third byte after the buffer's number" do
      memory_command(*"M-W".bytes, 0x00, 0x06, 3, 0xa0, 0xa1, 0xa2)
      expect(read_channel(2).first(2)).to eq([3, 0xa2])
    end

    it "hands out the rest of the buffer after the number" do
      expect(read_channel(2).length).to eq(255)
    end

    it "hands out the buffer rather than its number once written to" do
      drive.write(2, [0x41])
      expect(drive.read(2)).to eq([0x00, false])
    end

    it "hands out what M-W wrote" do
      memory_command(*"M-W".bytes, 0xfe, 0x06, 2, 0xc1, 0xc2)
      command("b-p 2 254")
      expect(read_channel(2)).to eq([0xc1, 0xc2])
    end

    it "shows M-R the block U1 read" do
      command("u1 2 0 18 1")
      memory_command(*"M-R".bytes, 0x10, 0x06, 2)
      expect(read_channel(15)).to eq([0x10, 0x11])
    end

    it "hands out the block a read job put in it" do
      memory_command(*"M-W".bytes, 0x0c, 0x00, 2, 18, 0)
      memory_command(*"M-W".bytes, 0x03, 0x00, 1, 0x80)
      command("b-p 2 254")
      expect(read_channel(2)).to eq([254, 255])
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

  describe "a LOAD of a name starting with *" do
    def memory_write(address, byte)
      drive.write(15, [*"M-W".bytes, address & 0xff, address >> 8, 1, byte])
    end

    before do
      allow(storage).to receive_messages(first_block: [17, 0], read_file_at: [0x00, 0xc0, 0x60])
    end

    it "takes the first file before any LOAD" do
      drive.open(0, "*")
      expect(read_channel(0)).to eq([0x01, 0x08, 0x2a])
    end

    it "reopens the file the last LOAD opened" do
      drive.open(0, "GAME")
      drive.open(0, "*")
      expect(storage).to have_received(:read_file_at).with(17, 0)
    end

    it "reopens the file at the block M-W put at $7E and $026F" do
      memory_write(0x7e, 17)
      memory_write(0x26f, 3)
      drive.open(0, "*")
      expect(read_channel(0)).to eq([0x00, 0xc0, 0x60])
    end

    it "keeps a LOAD's first block where M-R reads it" do
      drive.open(0, "GAME")
      drive.write(15, [*"M-R".bytes, 0x7e, 0x00, 1])
      expect(read_channel(15)).to eq([17])
    end

    it "looks the name up on other channels" do
      memory_write(0x7e, 17)
      drive.open(2, "*")
      expect(storage).not_to have_received(:read_file_at)
    end

    it "reports a block outside the image" do
      allow(storage).to receive(:read_file_at).and_return(nil)
      memory_write(0x7e, 99)
      drive.open(0, "*")
      expect(status).to eq("66,ILLEGAL TRACK OR SECTOR,99,00")
    end
  end

  describe "a disk change" do
    subject(:swapped) { described_class.new(other_disk, memory) }

    let(:memory) { Badline::KernalTrap::Drive::Memory.new }
    let(:drive) { described_class.new(storage, memory) }
    let(:other_disk) { instance_double(Badline::Storage::D64Image, read_block: Array.new(256, 0xee), block_error: nil) }

    before { drive.write(15, [*"M-W".bytes, 0x00, 0x05, 1, 0xaa]) }

    it "keeps the RAM the drive it replaces had" do
      swapped.write(15, [*"M-R".bytes, 0x00, 0x05, 1])
      expect(swapped.read(15)).to eq([0xaa, true])
    end

    it "runs read jobs on the new disk" do
      swapped.write(15, [*"M-W".bytes, 0x06, 0x00, 2, 18, 0])
      swapped.write(15, [*"M-W".bytes, 0x00, 0x00, 1, 0x80])
      swapped.write(15, [*"M-R".bytes, 0x00, 0x03, 1])
      expect(swapped.read(15)).to eq([0xee, true])
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
