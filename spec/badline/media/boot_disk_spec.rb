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
        .to eq([Badline::Drive1571, nil])
    end

    it "mounts it through the traps on a C128 in C64 mode" do
      machine = Badline::C128.new(mode: :c64)
      expect(Badline::Media.attach(machine, d64("CBM"))).to start_with("Mounted")
    end

    it "mounts it through the traps on a C64" do
      expect(Badline::Media.attach(Badline::Computer.new, d64("CBM"))).to start_with("Mounted")
    end
  end
end
