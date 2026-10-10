# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Drive1581::Disk do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "disk.d81") }

  # An image whose every block is filled with its logical track, its
  # sector and the byte's place, so a sector read off a track names the
  # blocks it holds.
  def numbered_image(errors = [])
    blocks = Array.new(3200) { |block| [(block / 40) + 1, block % 40, *Array.new(254) { |i| i & 0xff }] }
    File.binwrite(path, (blocks.flatten + errors).pack("C*"))
    path
  end

  def first_bytes(track, number) = track.sector([*track.sectors.first.id.bytes[0, 2], number, 2]).data.bytes

  after { FileUtils.remove_entry(dir) }

  describe "the .d81's sectors" do
    subject(:disk) { described_class.open(numbered_image) }

    it "puts logical track t on cylinder t - 1" do
      expect(first_bytes(disk.track(39, 0), 1)[0]).to eq(40)
    end

    it "puts logical sectors 0 and 1 in side 0's sector 1" do
      bytes = first_bytes(disk.track(0, 0), 1)
      expect([bytes[1], bytes[257]]).to eq([0, 1])
    end

    it "puts logical sectors 20 and 21 in side 1's sector 1" do
      bytes = first_bytes(disk.track(0, 1), 1)
      expect([bytes[1], bytes[257]]).to eq([20, 21])
    end

    it "puts logical sectors 38 and 39 in side 1's sector 10" do
      bytes = first_bytes(disk.track(5, 1), 10)
      expect([bytes[1], bytes[257]]).to eq([38, 39])
    end

    it "has no track past cylinder 79" do
      expect(disk.track(80, 0)).to be_nil
    end

    it "is writable when its image is" do
      expect(disk.write_protected?).to be(false)
    end
  end

  describe "an image with an error table" do
    # Cylinder 0, side 0, with the error table marking +block+ with
    # +code+.
    def marked(block, code)
      errors = Array.new(3200, 1)
      errors[block] = code
      described_class.open(numbered_image(errors)).track(0, 0)
    end

    it "loses the ID of a sector whose block is marked 20" do
      expect(marked(1, 2).sectors.map { |sector| sector.id.bytes[2] }).not_to include(1)
    end

    it "spoils the data CRC of a sector whose block is marked 23" do
      expect(marked(2, 5).sectors[1].data.good).to be(false)
    end

    it "loses the data field of a sector whose block is marked 22" do
      expect(marked(3, 4).sectors[1].data).to be_nil
    end
  end

  describe "writing" do
    subject!(:disk) { described_class.open(blank_d81(path)) }

    def rewrite(cylinder, side, number, byte)
      track = disk.track(cylinder, side)
      track.sector([cylinder, side, number, 2]).data.bytes = Array.new(512, byte)
      disk.write(cylinder, side, track)
    end

    it "stores a written sector's two blocks in the image on flush" do
      rewrite(2, 1, 3, 0x5a)
      disk.flush
      image = Badline::Storage::D81Image.new(path)
      expect([image.read_block(3, 24)[0], image.read_block(3, 25)[255]]).to eq([0x5a, 0x5a])
    end

    it "leaves the image alone until the flush" do
      before = File.binread(path)
      rewrite(2, 1, 3, 0x5a)
      expect(File.binread(path)).to eq(before)
    end

    it "notes a track written since the last flush" do
      rewrite(0, 0, 1, 1)
      expect(disk).to be_written
    end

    it "keeps a track formatted another way on the disk alone" do
      disk.write(4, 0, Badline::Drive1581::Track.new([]))
      disk.flush
      expect(disk.track(4, 0).sectors).to be_empty
    end
  end

  describe "a read-only image" do
    subject(:disk) { described_class.open(blank_d81(path), read_only: true) }

    it "is write-protected" do
      expect(disk.write_protected?).to be(true)
    end
  end

  describe "a snapshot" do
    let(:disk) { described_class.open(blank_d81(path)) }

    def round_trip(current)
      out = Badline::Snapshot::StateWriter.new
      disk.save_state(out)
      Badline::Drive1581::Disk::SavedState.load(Badline::Snapshot::StateReader.new(out.state), current)
    end

    before do
      track = disk.track(7, 0)
      track.sectors.first.data.bytes = Array.new(512, 0x77)
      disk.write(7, 0, track)
    end

    it "brings back a track written since the disk went in" do
      expect(round_trip(nil).track(7, 0).sectors.first.data.bytes[0]).to eq(0x77)
    end

    it "reuses the disk in when it's the one the state names" do
      expect(round_trip(disk)).to equal(disk)
    end

    it "keeps the tracks still to flush" do
      expect(round_trip(nil)).to be_written
    end
  end
end
