# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Drive1541::Disk, ".from_g64" do
  subject(:disk) { described_class.from_g64(image) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "disk.g64") }
  let(:image) { Badline::Storage::G64Image.new(path) }
  # Track 1, track 1.5 and track 18 at non-standard lengths, and track 42.
  let(:tracks) do
    { 0 => [Array.new(7821) { |i| i & 0xff }, 3], 1 => [Array.new(7000, 0x55), 3],
      34 => [Array.new(6974) { |i| (i * 3) & 0xff }, 2], 82 => [Array.new(6250, 0x55), 0] }
  end

  before { Badline::Storage::G64Image.create(path, tracks) }

  after { FileUtils.remove_entry(dir) }

  it "holds each of the image's half tracks at its half track, as long as the image has it" do
    expect([2, 3, 36, 84].map { |half| [disk.track(half).bytes, disk.track(half).zone] }).to eq(tracks.values)
  end

  it "is what .open makes of a .g64" do
    expect(described_class.open(path).track(2).bytes).to eq(tracks[0].first)
  end

  it "has nothing where the image has no data" do
    expect((2..84).count { |half| disk.track(half) }).to eq(4)
  end

  describe "#flush" do
    it "writes the tracks back into the image as they are" do
      disk.track(36).bytes[100, 3] = [1, 2, 3]
      disk.written(36)
      disk.flush
      expect(Badline::Storage::G64Image.new(path).track(34)).to eq([disk.track(36).bytes, 2])
    end

    it "leaves an image it didn't change byte for byte as it was" do
      before = File.binread(path)
      [2, 3, 36, 84].each { |half| disk.written(half) }
      disk.flush
      expect(File.binread(path)).to eq(before)
    end

    it "gives a half track the head wrote on a block of its own" do
      disk.writable_track(51, 1).bytes[0, 2] = [0xff, 0xff]
      disk.written(51)
      disk.flush
      expect(Badline::Storage::G64Image.new(path).track(49)).to eq([disk.track(51).bytes, 1])
    end

    it "reads each track once" do
      disk.written(36)
      disk.flush
      allow(image).to receive(:store_tracks)
      disk.flush
      expect(image).not_to have_received(:store_tracks)
    end
  end
end
