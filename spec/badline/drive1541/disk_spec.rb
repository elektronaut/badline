# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Drive1541::Disk do
  include BlankDisk

  subject(:disk) { described_class.from_d64(image) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "disk.d64") }
  let(:image) { Badline::Storage::D64Image.new(path) }
  let(:gcr) { Badline::Drive1541::GCR }

  before do
    blank_d64(path)
    bytes = File.binread(path).bytes
    bytes[d64_offset(18, 0) + 0xa2, 2] = [0x41, 0x42] # disk ID "AB"
    # Every block a different pattern, so a block read from the wrong
    # place shows.
    BlankDisk::D64_SECTORS.each_with_index do |sectors, t|
      sectors.times do |s|
        next if t == 17 && s < 2

        bytes[d64_offset(t + 1, s), 256] = Array.new(256) { |i| ((i * (t + 3)) + s) & 0xff }
      end
    end
    File.binwrite(path, bytes.pack("C*"))
  end

  after { FileUtils.remove_entry(dir) }

  # Each block on a track, in the order the head meets them: the bytes
  # after each SYNC mark, decoded, sized by the ID they start with.
  def blocks(track_bytes)
    found = []
    i = 0
    while i < track_bytes.length
      if track_bytes[i] == 0xff
        i += 1 while track_bytes[i] == 0xff
        length = gcr.decode(track_bytes[i, 5]).first == 0x08 ? 10 : 325
        found << gcr.decode(track_bytes[i, length])
        i += length
      else
        i += 1
      end
    end
    found
  end

  def sectors(track) = BlankDisk::D64_SECTORS[track - 1]

  # The blocks of a track whose data doesn't read back as the image holds
  # it, as [track, sector].
  def mismatched(track)
    data = blocks(disk.track(track * 2).bytes).each_slice(2).map { |_header, block| block[1, 256] }
    (0...sectors(track)).reject { |sector| data[sector] == image.read_block(track, sector) }
                        .map { |sector| [track, sector] }
  end

  it "holds each track at its whole half track" do
    expect([disk.track(2), disk.track(3), disk.track(70), disk.track(71)].map(&:nil?))
      .to eq([false, true, false, true])
  end

  it "holds the 35 tracks of a 35-track image" do
    expect((1..42).count { |track| disk.track(track * 2) }).to eq(35)
  end

  {
    1 => [3, 7692], 17 => [3, 7692], 18 => [2, 7142], 24 => [2, 7142],
    25 => [1, 6666], 30 => [1, 6666], 31 => [0, 6250], 35 => [0, 6250]
  }.each do |track, (zone, length)|
    it "writes track #{track} in zone #{zone}, #{length} bytes around" do
      expect([disk.track(track * 2).zone, disk.track(track * 2).length]).to eq([zone, length])
    end
  end

  it "reads every block back as the image holds it, in sector order" do
    expect((1..35).flat_map { |track| mismatched(track) }).to be_empty
  end

  it "heads each block with its sector, track and the disk ID" do
    headers = blocks(disk.track(36).bytes).each_slice(2).map(&:first)
    expect(headers[5]).to eq([0x08, 5 ^ 18 ^ 0x42 ^ 0x41, 5, 18, 0x42, 0x41, 0x0f, 0x0f])
  end

  it "closes each data block with the XOR of its bytes" do
    block = blocks(disk.track(2).bytes)[3]
    expect([block[0], block[257], block[258, 2]])
      .to eq([0x07, block[1, 256].reduce(:^), [0, 0]])
  end

  it "lays out a sector as SYNC, header, gap, SYNC and data" do
    bytes = disk.track(2).bytes
    expect([bytes[0, 5], bytes[15, 9], bytes[24, 5], gcr.decode(bytes[29, 5]).first])
      .to eq([[0xff] * 5, [0x55] * 9, [0xff] * 5, 0x07])
  end

  it "fills the rest of the track with gap bytes" do
    bytes = disk.track(70).bytes
    expect(bytes.last(10)).to eq([0x55] * 10)
  end

  it "puts every sector of a track in, once" do
    counts = (1..35).map { |track| blocks(disk.track(track * 2).bytes).length / 2 }
    expect(counts).to eq(BlankDisk::D64_SECTORS)
  end

  it "never has ten 1 bits in a row outside a SYNC mark" do
    bits = disk.track(2).bytes.map { |byte| format("%08b", byte) }.join
    runs = bits.scan(/1+/).map(&:length).reject { |run| run >= 40 }
    expect(runs.max).to be < 10
  end

  context "with 40 tracks" do
    before do
      File.binwrite(path, File.binread(path) + ("\0".b * 5 * 17 * 256))
    end

    it "holds 40 tracks, the last in zone 0" do
      expect([(1..42).count { |track| disk.track(track * 2) }, disk.track(80).zone]).to eq([40, 0])
    end
  end

  context "with an error table" do
    # Error codes: 2 is error 20, 3 is 21, 4 is 22, 5 is 23, 9 is 27, 11 is 29
    before do
      errors = Array.new(683, 1)
      { 0 => 2, 1 => 3, 2 => 4, 3 => 5, 4 => 9, 5 => 11 }.each { |sector, code| errors[sector] = code }
      File.binwrite(path, File.binread(path) + errors.pack("C*"))
    end

    # Track 1's sectors follow each other every 366 bytes: 354 and a gap
    # of 12.
    def sector_at(sector)
      disk.track(2).bytes[sector * 366, described_class::SECTOR_LENGTH]
    end

    def header(sector) = gcr.decode(sector_at(sector)[5, 10])

    def data(sector) = gcr.decode(sector_at(sector)[29, 325])

    it "hides the header ID for error 20" do
      expect(header(0)[0]).to eq(0x00)
    end

    it "leaves out the SYNC marks for error 21" do
      expect([sector_at(1)[0, 5], sector_at(1)[24, 5]]).to eq([[0x55] * 5] * 2)
    end

    it "hides the data block ID for error 22" do
      expect(data(2)[0]).to eq(0x00)
    end

    it "spoils the data checksum for error 23" do
      expect(data(3)[257]).to eq(data(3)[1, 256].reduce(:^) ^ 0xff)
    end

    it "spoils the header checksum for error 27" do
      expect(header(4)[1]).to eq(4 ^ 1 ^ 0x42 ^ 0x41 ^ 0xff)
    end

    it "writes another disk ID for error 29" do
      expect(header(5)[4, 2]).to eq([0x42, 0x41 ^ 0xff])
    end

    it "writes the other blocks cleanly" do
      expect([header(6)[0, 2], data(6)[0]]).to eq([[0x08, 6 ^ 1 ^ 0x42 ^ 0x41], 0x07])
    end
  end
end
