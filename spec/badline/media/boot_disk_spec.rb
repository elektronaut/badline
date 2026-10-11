# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../support/blank_disk"

describe Badline::Media::BootDisk do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  # A .d64 whose track 1, sector 0 starts with +signature+.
  def d64(signature)
    path = blank_d64(File.join(dir, "#{signature}.d64"))
    bytes = File.binread(path).bytes
    bytes[0, 3] = signature.bytes
    File.binwrite(path, bytes.pack("C*"))
    path
  end

  # A .g64, or a .g71 with 168 half tracks, holding the GCR of d64(signature).
  def gcr(signature, extension, half_tracks = 84)
    disk = Badline::Drives::Model1541::Disk.open(d64(signature))
    tracks = (2..70).step(2).to_h { |half| [half - 2, [disk.track(half).bytes, disk.track(half).zone]] }
    path = File.join(dir, "#{signature}#{extension}")
    Badline::Storage::G64Image.create(path, tracks, half_tracks:)
    path
  end

  def g71(signature)
    path = gcr(signature, ".g71", 168)
    data = File.binread(path)
    data[0, 8] = "GCR-1571"
    File.binwrite(path, data)
    path
  end

  def d81_with(name)
    path = blank_d81(File.join(dir, "auto.d81"))
    Badline::Storage::D81Image.new(path).write_file(name, [0x00, 0x20, 0x60], type: :usr)
    path
  end

  it "boots a disk whose track 1, sector 0 starts with CBM" do
    expect(described_class.boot?(d64("CBM"))).to be(true)
  end

  it "leaves a disk with another signature to the autostart" do
    expect(described_class.boot?(d64("CBX"))).to be(false)
  end

  it "boots a .g64 whose track 1, sector 0 starts with CBM" do
    expect(described_class.boot?(gcr("CBM", ".g64"))).to be(true)
  end

  it "leaves a .g64 with another signature to the autostart" do
    expect(described_class.boot?(gcr("CBX", ".g64"))).to be(false)
  end

  it "boots a .g71 whose track 1, sector 0 starts with CBM" do
    expect(described_class.boot?(g71("CBM"))).to be(true)
  end

  it "leaves a .g71 with another signature to the autostart" do
    expect(described_class.boot?(g71("CBX"))).to be(false)
  end

  it "boots a .d81 with the 1581's auto-boot file" do
    expect(described_class.boot?(d81_with("copyright cbm 86"))).to be(true)
  end

  it "leaves a .d81 with other files to the autostart" do
    expect(described_class.boot?(d81_with("program"))).to be(false)
  end

  describe "Media.attach" do
    it "puts a C128 boot disk in a true drive, with nothing typed" do
      machine = Badline::C128.new(mode: :c128)
      Badline::Media.attach(machine, d64("CBM"))
      expect([machine.drive1571.class, machine.instance_variable_get(:@pending_keys)])
        .to eq([Badline::Drives::Model1571, nil])
    end

    it "says a .g64 boot disk boots at power-on" do
      machine = Badline::C128.new(mode: :c128)
      expect(Badline::Media.attach(machine, gcr("CBM", ".g64"))).to end_with(", to boot at power-on")
    end

    it "mounts it through the traps on a C128 in C64 mode" do
      machine = Badline::C128.new(mode: :c64)
      expect(Badline::Media.attach(machine, d64("CBM"))).to start_with("Mounted")
    end

    it "mounts it through the traps on a C64" do
      expect(Badline::Media.attach(Badline::C64.new, d64("CBM"))).to start_with("Mounted")
    end
  end
end
