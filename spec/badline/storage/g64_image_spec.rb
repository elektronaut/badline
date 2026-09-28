# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::G64Image do
  subject(:image) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "disk.g64") }
  let(:tracks) do
    { 0 => [pattern(7692, 1), 3], 1 => [pattern(7700, 2), 3], 34 => [pattern(7142, 3), 2],
      68 => [pattern(6250, 4), 0] }
  end

  # Each track a different pattern, so a track read from the wrong place
  # shows.
  def pattern(length, seed) = Array.new(length) { |i| ((i * 7) + seed) & 0xff }

  # An image laid out by hand: the header, the two tables for
  # +half_tracks+ entries, and each block packed right after the last,
  # +tracks+ as {entry => [bytes, speed]}, and speed maps after them,
  # +maps+ as {entry => bytes}.
  def g64(tracks, half_tracks: 84, max: 7928, maps: {})
    offsets = Array.new(half_tracks, 0)
    speeds = Array.new(half_tracks, 0)
    body = +"".b
    start = 12 + (half_tracks * 8)
    tracks.each do |entry, (bytes, speed)|
      offsets[entry] = start + body.bytesize
      speeds[entry] = speed
      body << [bytes.length].pack("v") << bytes.pack("C*")
    end
    maps.each do |entry, map|
      speeds[entry] = start + body.bytesize
      body << map.pack("C*")
    end
    "GCR-1541\x00".b + [half_tracks, max].pack("Cv") + offsets.pack("V*") + speeds.pack("V*") + body
  end

  before { File.binwrite(path, g64(tracks)) }

  after { FileUtils.remove_entry(dir) }

  describe "#track" do
    it "reads each track's bytes and zone by its table entry" do
      expect(tracks.keys.map { |entry| image.track(entry) }).to eq(tracks.values)
    end

    it "reads a half track" do
      expect(image.track(1).first.length).to eq(7700)
    end

    it "has nothing where the table has no block" do
      expect([2, 35, 83].map { |entry| image.track(entry) }).to all(be_nil)
    end

    it "has nothing past the tables" do
      expect(image.track(84)).to be_nil
    end

    it "reads each byte's zone from a speed map, the first byte's in the top bits" do
      File.binwrite(path, g64({ 0 => [pattern(8, 1), 0] }, maps: { 0 => [0b11100100, 0b00011011] }))
      expect(image.speeds(0)).to eq([3, 2, 1, 0, 0, 1, 2, 3])
    end

    it "has no speeds for a track in one zone" do
      File.binwrite(path, g64({ 0 => [pattern(8, 1), 0] }, maps: { 0 => [0b10101010, 0b10101010] }))
      expect([image.speeds(0), image.speeds(1), image.speeds(2)]).to eq([nil, nil, nil])
    end

    it "takes the zone most of a speed-mapped track's bytes were written in" do
      map = ([0b10101010] * 1500) + ([0b11111111] * 423)
      File.binwrite(path, g64({ 0 => [pattern(7692, 1), 0] }, maps: { 0 => map }))
      expect(image.track(0).last).to eq(2)
    end
  end

  it "reads the header's table size and longest track" do
    expect([image.half_tracks, image.max_track_size]).to eq([84, 7928])
  end

  it "refuses a file without the signature" do
    File.binwrite(path, "GCR-1571".b + ("\x00" * 700))
    expect { image }.to raise_error(described_class::FormatError)
  end

  it "refuses a version it doesn't know" do
    File.binwrite(path, "GCR-1541\x01\x54\xf8\x1e".b + ("\x00" * 672))
    expect { image }.to raise_error(described_class::FormatError, /version/)
  end

  describe "a malformed image" do
    # The image with table entry +entry+ of the offsets (or of the speeds
    # with +table+ 1) set to +value+.
    def patched(value, entry: 0, table: 0)
      data = g64(tracks)
      data[12 + (((table * 84) + entry) * 4), 4] = [value].pack("V")
      data
    end

    def format_error(data)
      File.binwrite(path, data)
      described_class.new(path)
    rescue described_class::FormatError => e
      e.message
    end

    it "refuses a header cut short" do
      expect(format_error("GCR-1541\x00\x54".b)).to include("header is cut short")
    end

    it "refuses tables cut short" do
      expect(format_error(g64(tracks).byteslice(0, 300))).to include("tables are cut short")
    end

    it "refuses a track offset past the end of the file" do
      expect(format_error(patched(g64(tracks).bytesize + 10))).to include("entry 0 runs past the end")
    end

    it "refuses a track that runs past the end of the file" do
      expect(format_error(g64(tracks).byteslice(0, g64(tracks).bytesize - 1))).to include("entry 68 runs past the end")
    end

    it "refuses a track offset into the tables" do
      expect(format_error(patched(40, entry: 34))).to include("entry 34 points into the header or its tables")
    end

    it "refuses a speed map past the end of the file" do
      expect(format_error(patched(g64(tracks).bytesize, table: 1))).to include("speed map of track entry 0 runs past")
    end

    it "refuses a speed map in the tables" do
      expect(format_error(patched(100, table: 1))).to include("speed map of track entry 0 points into")
    end
  end

  describe "#writable?" do
    it "is true of a writable host file" do
      expect(image).to be_writable
    end

    it "is false of an image opened read-only" do
      expect(described_class.new(path, read_only: true)).not_to be_writable
    end
  end

  describe "#store_tracks" do
    it "writes an unchanged track back byte for byte" do
      before = File.binread(path)
      image.store_tracks(0 => image.track(0), 1 => image.track(1))
      expect(File.binread(path)).to eq(before)
    end

    it "writes a changed track into its own block" do
      bytes = pattern(7142, 9)
      image.store_tracks(34 => [bytes, 2])
      expect([File.size(path), described_class.new(path).track(34)]).to eq([g64(tracks).bytesize, [bytes, 2]])
    end

    it "leaves the other tracks alone" do
      image.store_tracks(34 => [pattern(7142, 9), 2])
      reread = described_class.new(path)
      expect([0, 1, 68].map { |entry| reread.track(entry) }).to eq(tracks.values_at(0, 1, 68))
    end

    it "appends a block for a half track that had none, in its zone" do
      bytes = pattern(6666, 5)
      image.store_tracks(49 => [bytes, 1])
      reread = described_class.new(path)
      expect([reread.track(49), File.size(path)]).to eq([[bytes, 1], g64(tracks).bytesize + 2 + 7928])
    end

    it "appends a block for a track that outgrew its own" do
      bytes = pattern(7800, 6)
      image.store_tracks(0 => [bytes, 3])
      reread = described_class.new(path)
      expect([reread.track(0), reread.track(1)]).to eq([[bytes, 3], tracks[1]])
    end

    it "raises the header's longest track for a longer one" do
      image.store_tracks(2 => [pattern(8000, 7), 3])
      expect([described_class.new(path).max_track_size, image.max_track_size]).to eq([8000, 8000])
    end

    it "gives a speed-mapped track the zone it was written in" do
      map = ([0b01010101] * 1000) + ([0b11111111] * 923)
      File.binwrite(path, g64({ 0 => [pattern(7692, 1), 0] }, maps: { 0 => map }))
      image.store_tracks(0 => [pattern(7692, 8), 2])
      reread = described_class.new(path)
      expect([reread.track(0).last, reread.speeds(0)]).to eq([2, nil])
    end

    context "when the image was opened read-only" do
      subject(:image) { described_class.new(path, read_only: true) }

      def failed_write
        image.store_tracks(5 => [pattern(7692, 8), 3])
      rescue Badline::Storage::WriteError => e
        e.code
      end

      it "fails as a write-protected disk" do
        expect(failed_write).to eq(26)
      end

      it "leaves the host file alone" do
        before = File.binread(path)
        failed_write
        expect(File.binread(path)).to eq(before)
      end
    end

    context "when the host file won't take writes" do
      before { allow(File).to receive(:binwrite).and_raise(Errno::EACCES) }

      def failed_write
        image.store_tracks(5 => [pattern(7692, 8), 3])
      rescue Badline::Storage::WriteError => e
        e.code
      end

      it "fails as a write-protected disk" do
        expect(failed_write).to eq(26)
      end

      it "keeps reading the image as it was" do
        failed_write
        expect(image.track(5)).to be_nil
      end
    end
  end

  describe ".create" do
    it "lays out an image that reads back its tracks" do
      created = described_class.create(File.join(dir, "new.g64"), tracks)
      expect(tracks.keys.map { |entry| created.track(entry) }).to eq(tracks.values)
    end

    it "pads every block to the longest track" do
      described_class.create(File.join(dir, "new.g64"), tracks)
      expect(File.size(File.join(dir, "new.g64"))).to eq(12 + (84 * 8) + (4 * (2 + 7928)))
    end
  end

  it "is writable when the host file is" do
    expect(image.writable?).to be(true)
  end

  it "isn't when the host file isn't", :file_permissions do
    File.chmod(0o444, path)
    expect(image.writable?).to be(false)
  end
end
