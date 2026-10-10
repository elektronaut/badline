# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Drive1541::Disk, ".image_for" do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def g64(name)
    File.join(dir, name).tap { |path| Badline::Storage::G64Image.create(path, { 0 => [Array.new(7000, 0x55), 3] }) }
  end

  it "opens a .g64 as a G64Image" do
    expect(described_class.image_for(g64("disk.g64"), true)).to be_an_instance_of(Badline::Storage::G64Image)
  end

  it "opens a .g71 as a G64Image" do
    expect(described_class.image_for(g64("DISK.G71"), true)).to be_an_instance_of(Badline::Storage::G64Image)
  end

  it "opens a .d71 as a D71Image" do
    path = File.join(dir, "disk.d71").tap { |at| File.binwrite(at, ("\x00" * 349_696).b) }
    expect(described_class.image_for(path, true)).to be_an_instance_of(Badline::Storage::D71Image)
  end

  it "opens anything else as a D64Image" do
    path = blank_d64(File.join(dir, "disk.img"))
    expect(described_class.image_for(path, true)).to be_an_instance_of(Badline::Storage::D64Image)
  end

  it "opens it write-protected when asked" do
    expect(described_class.image_for(blank_d64(File.join(dir, "disk.d64")), true).writable?).to be(false)
  end
end
