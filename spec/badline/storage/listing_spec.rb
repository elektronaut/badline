# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Storage::Listing do
  subject(:listing) do
    described_class.new(name: "ORACLE DISK".bytes + ([0xa0] * 5), id: "AB".bytes + [0xa0] + "2A".bytes,
                        entries:, blocks_free: 664)
  end

  let(:entries) do
    [entry("SHORT", 2, 1),
     entry("SIXTEENCHARSNAME", 1, 12),
     entry("UNCLOSED", 2, 123, closed: false),
     entry("LOCKED", 2, 1234, locked: true),
     entry("DELETED", 0, 0),
     entry("RELFILE", 4, 5),
     entry("USRFILE", 3, 99),
     described_class::Entry.new(name: "HID".bytes + [0xa0] + ",8,1".bytes + ([0xa0] * 8), type: 2, blocks: 7,
                                closed: true, locked: false),
     entry("NEXT", 2, 2)]
  end

  # A true 1541 (Drive1541 running the DOS ROM) sent these lines for a
  # D64 with this directory, loaded at $0801 and relinked there, so only
  # the links differ.
  let(:drive_listing) do
    hex(<<~HEX)
      01 04 1f 04 00 00 12 22 4f 52 41 43 4c 45 20 44 49 53 4b 20 20 20 20 20 22 20 41 42 20 32 41 00
      3f 04 01 00 20 20 20 22 53 48 4f 52 54 22 20 20 20 20 20 20 20 20 20 20 20 20 50 52 47 20 20 00
      5f 04 0c 00 20 20 22 53 49 58 54 45 45 4e 43 48 41 52 53 4e 41 4d 45 22 20 53 45 51 20 20 20 00
      7f 04 7b 00 20 22 55 4e 43 4c 4f 53 45 44 22 20 20 20 20 20 20 20 20 2a 50 52 47 20 20 20 20 00
      9f 04 d2 04 20 22 4c 4f 43 4b 45 44 22 20 20 20 20 20 20 20 20 20 20 20 50 52 47 3c 20 20 20 00
      bf 04 00 00 20 20 20 22 44 45 4c 45 54 45 44 22 20 20 20 20 20 20 20 20 20 20 44 45 4c 20 20 00
      df 04 05 00 20 20 20 22 52 45 4c 46 49 4c 45 22 20 20 20 20 20 20 20 20 20 20 52 45 4c 20 20 00
      ff 04 63 00 20 20 22 55 53 52 46 49 4c 45 22 20 20 20 20 20 20 20 20 20 20 55 53 52 20 20 20 00
      1f 05 07 00 20 20 20 22 48 49 44 22 2c 38 2c 31 20 20 20 20 20 20 20 20 20 20 50 52 47 20 20 00
      3f 05 02 00 20 20 20 22 4e 45 58 54 22 20 20 20 20 20 20 20 20 20 20 20 20 20 50 52 47 20 20 00
      5d 05 98 02 42 4c 4f 43 4b 53 20 46 52 45 45 2e 20 20 20 20 20 20 20 20 20 20 20 20 20 00
      00 00
    HEX
  end

  def entry(name, type, blocks, closed: true, locked: false)
    described_class::Entry.new(name: described_class.encode(name), type:, blocks:, closed:, locked:)
  end

  def hex(text) = text.split.map { |byte| byte.to_i(16) }

  # The program's lines as [line number, text], following the links.
  def lines(bytes)
    address = described_class::LOAD_ADDRESS
    memory = bytes[2..]
    result = []
    loop do
      offset = address - described_class::LOAD_ADDRESS
      link = memory[offset] | (memory[offset + 1] << 8)
      break if link.zero?

      text = memory[(offset + 4)...(link - described_class::LOAD_ADDRESS - 1)]
      result << [memory[offset + 2] | (memory[offset + 3] << 8), text.pack("C*")]
      address = link
    end
    result
  end

  describe "#bytes" do
    it "lists the directory as a 1541 does" do
      expect(listing.bytes).to eq(drive_listing)
    end

    it "loads at $0401" do
      expect(listing.bytes.first(2)).to eq([0x01, 0x04])
    end

    it "shows the disk name and ID in reverse video on line 0" do
      expect(lines(listing.bytes).first).to eq([0, "\x12\"ORACLE DISK     \" AB 2A"])
    end

    it "numbers each file's line by its blocks" do
      expect(lines(listing.bytes)[1..-2].map(&:first)).to eq([1, 12, 123, 1234, 0, 5, 99, 7, 2])
    end

    it "ends with the free blocks" do
      expect(lines(listing.bytes).last).to eq([664, "BLOCKS FREE.#{' ' * 13}"])
    end

    it "marks a file that was never closed" do
      expect(lines(listing.bytes)[3].last).to eq(" \"UNCLOSED\"        *PRG    ")
    end

    it "marks a locked file" do
      expect(lines(listing.bytes)[4].last).to eq(" \"LOCKED\"           PRG<   ")
    end

    it "lists only the files a pattern names" do
      names = lines(listing.bytes("$0:S*,U*"))[1..-2].map { |line| line.last[/"(.*)"/, 1] }
      expect(names).to eq(%w[SHORT SIXTEENCHARSNAME UNCLOSED USRFILE])
    end

    it "lists every file for a drive number without a pattern" do
      expect(lines(listing.bytes("$0")).length).to eq(11)
    end

    it "keeps the header and the free blocks when no file matches" do
      expect(lines(listing.bytes("$:NOTHING")).map(&:first)).to eq([0, 664])
    end
  end

  describe ".program" do
    it "counts 254 bytes to a block" do
      expect([1, 254, 255, 508].map { |length| described_class.program("x", length).blocks }).to eq([1, 1, 2, 2])
    end

    it "lists a host name in upper case, padded with shifted spaces" do
      expect(described_class.program("game", 10).name).to eq("GAME".bytes + ([0xa0] * 12))
    end
  end

  describe "a disk image's listing" do
    include BlankDisk

    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def free_line = "BLOCKS FREE.#{' ' * 13}"

    # A blank D64 whose first directory slots hold [type, name, blocks].
    def d64_with(slots)
      path = blank_d64(File.join(dir, "test.d64"))
      raw = File.binread(path).bytes
      slots.each_with_index do |(type, name, blocks), i|
        at = d64_offset(18, 1) + (32 * i)
        raw[at + 2] = type
        raw[at + 5, 16] = described_class.encode(name)
        raw[at + 30, 2] = [blocks & 0xff, blocks >> 8]
      end
      File.binwrite(path, raw.pack("C*"))
      Badline::Storage::D64Image.new(path)
    end

    it "lists a D64" do
      image = Badline::Storage::D64Image.new(blank_d64(File.join(dir, "test.d64"), name: "GAMES"))
      image.write_file("hello", [0x01, 0x08] + Array.new(300, 0), type: :prg)
      expect(lines(image.directory.bytes)[1..]).to eq([[2, "   \"HELLO\"            PRG  "], [662, free_line]])
    end

    it "reads a D64 entry's type, flags and blocks, and skips a scratched one" do
      image = d64_with([[0x00, "GONE", 3], [0x02, "OPEN", 4], [0xc1, "KEPT", 300]])
      expect(image.directory.entries.map(&:to_h)).to eq(
        [{ name: described_class.encode("OPEN"), type: 2, blocks: 4, closed: false, locked: false },
         { name: described_class.encode("KEPT"), type: 1, blocks: 300, closed: true, locked: true }]
      )
    end

    it "lists a D81" do
      image = Badline::Storage::D81Image.new(blank_d81(File.join(dir, "test.d81"), name: "GAMES"))
      image.write_file("notes", [0x41], type: :seq)
      expect(lines(image.directory.bytes)[1..]).to eq([[1, "   \"NOTES\"            SEQ  "], [3159, free_line]])
    end
  end
end
