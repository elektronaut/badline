# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/blank_disk"

describe Badline::Frontend::MenuMedia do
  include BlankDisk

  subject(:media) { described_class.new("", false).tap { |menu_media| menu_media.computer = computer } }

  let(:computer) { Badline::Computer.new }
  let(:dir) { Dir.mktmpdir }
  let(:first) { blank_d64(File.join(dir, "game disk1.d64")) }
  let(:second) { blank_d64(File.join(dir, "game disk2.d64")) }

  after { FileUtils.remove_entry(dir) }

  def crt(name)
    File.join(dir, name).tap do |path|
      header = "C64 CARTRIDGE   ".b + [0x40, 0x0100, 0, 0, 1].pack("NnnCC") + ("\x00" * 6) + "GAME".ljust(32, "\x00")
      chip = "CHIP".b + [0x2010, 0, 0, 0x8000, 0x2000].pack("Nn4") + ([0x42] * 0x2000).pack("C*")
      File.binwrite(path, header + chip)
    end
  end

  def storage = computer.instance_variable_get(:@drive).instance_variable_get(:@storage)

  it "puts a disk in write-protected unless told otherwise" do
    media.insert(:disk, first)
    expect([media.disk_path, storage.read_only?]).to eq([first, true])
  end

  it "puts the disk in again, writable, when WRITABLE goes on" do
    media.insert(:disk, first)
    media.drive(:unprotect)
    expect(storage.read_only?).to be(false)
  end

  it "keeps the setting for the next disk" do
    media.drive(:unprotect)
    media.insert(:disk, second)
    expect(storage.read_only?).to be(false)
  end

  it "steps through the disk's set" do
    second
    media.insert(:disk, first)
    media.drive(:next_disk)
    expect([media.disk_set.size, media.disk_path]).to eq([2, second])
  end

  it "stays on the set's last disk" do
    first
    media.insert(:disk, second)
    media.drive(:next_disk)
    expect(media.disk_path).to eq(second)
  end

  it "takes the disk out" do
    media.insert(:disk, first)
    media.drive(:eject_disk)
    expect([media.inserted?, media.disk_path]).to eq([false, ""])
  end

  it "keeps what went wrong with a disk" do
    media.insert(:disk, File.join(dir, "missing.d64"))
    expect(media.problem).not_to be_empty
  end

  it "attaches a cartridge, power cycling the machine" do
    expect([media.attach_cartridge(crt("game.crt")), media.cartridge_name]).to eq([true, "GAME"])
  end

  it "takes the cartridge out" do
    media.attach_cartridge(crt("game.crt"))
    media.remove_cartridge
    expect(computer.address_bus.cartridge).to be_nil
  end

  it "starts a file in a new machine, as the command line does" do
    started = media.start(Badline::Options.parse([]), first)
    expect([started.equal?(computer), started.mounted?, media.disk_path]).to eq([false, true, first])
  end

  it "starts nothing from a file it can't read" do
    File.write(File.join(dir, "bad.crt"), "junk")
    expect(media.start(Badline::Options.parse([]), File.join(dir, "bad.crt"))).to be_nil
  end
end
