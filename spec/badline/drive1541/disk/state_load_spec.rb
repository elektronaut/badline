# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Drive1541::Disk::State, ".load" do
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "disk.g64") }
  let(:tracks) { { 0 => [Array.new(7000) { |i| i & 0xff }, 3], 34 => [Array.new(6500, 0x55), 2] } }
  let(:saved) { Badline::Drive1541::Disk.open(path) }

  before { Badline::Storage::G64Image.create(path, tracks) }

  after { FileUtils.remove_entry(dir) }

  def restored(detached: false)
    out = Badline::Snapshot::StateWriter.new
    saved.save_state(out)
    File.delete(path)
    described_class.load(Badline::Snapshot::StateReader.new(out.state, detached:), nil)
  end

  it "keeps the state's tracks once the image file is gone" do
    disk = restored
    expect([2, 36].map { |half| [disk.track(half).bytes, disk.track(half).zone] }).to eq(tracks.values)
  end

  it "is write-protected once the image file is gone" do
    expect(restored).to be_write_protected
  end

  it "names the image it was opened from" do
    expect(restored.path).to eq(File.expand_path(path))
  end

  it "takes writes for a detached reader" do
    expect(restored(detached: true)).not_to be_write_protected
  end
end
