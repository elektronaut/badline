# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/blank_disk"

describe Badline::Frontend::MenuMedia do
  include BlankDisk

  subject(:media) { described_class.new("", false, {}).tap { |menu_media| menu_media.computer = computer } }

  let(:computer) { Badline::C64.new }
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

  def plus4_crt(bank:)
    File.join(dir, "plus4.crt").tap do |path|
      header = "PLUS4 CARTRIDGE ".b + [0x40, 0x0100, 0, 0, 0].pack("NnnCC") + ("\x00" * 6) + "GAME".ljust(32, "\x00")
      chip = "CHIP".b + [0x0110, 0, bank, 0x8000, 0x0100].pack("Nn4") + ([0x42] * 0x0100).pack("C*")
      File.binwrite(path, header + chip)
    end
  end

  def named_crt(name, slot)
    File.join(dir, "#{name}.crt").tap do |path|
      header = "PLUS4 CARTRIDGE ".b + [0x40, 0x0100, 0, 0, 0].pack("NnnCC") + ("\x00" * 6) + [name.upcase].pack("a32")
      bank, address = Badline::Media::Plus4Media::SLOTS.fetch(slot)
      File.binwrite(path, header + "CHIP".b + [0x0110, 0, bank, address, 0x0100].pack("Nn4") + ("\x42" * 0x0100))
    end
  end

  def rom_image(name, size) = File.join(dir, name).tap { |path| File.binwrite(path, "\x11" * size) }

  def quietly
    stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = stdout
  end

  def storage = computer.instance_variable_get(:@dos).instance_variable_get(:@storage)

  def start_quietly(path)
    stdout = $stdout
    $stdout = StringIO.new
    media.start(Badline::Options.parse([]), path)
  ensure
    $stdout = stdout
  end

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

  it "puts a list's first disk in and steps through the list" do
    File.write(File.join(dir, "game.m3u"), "#{File.basename(second)}\n#{File.basename(first)}\n")
    media.insert(:disk, File.join(dir, "game.m3u"))
    media.drive(:next_disk)
    expect([media.disk_set, media.disk_path]).to eq([[second, first], first])
  end

  it "starts on the command line's list" do
    File.write(File.join(dir, "game.vfl"), "UNIT 8\n#{second}\n#{first}\n")
    media = described_class.new(File.join(dir, "game.vfl"), false, {})
    media.computer = computer
    Badline::Media.attach(computer, File.join(dir, "game.vfl"), autostart: false)
    expect([media.disk_path, media.disk_set]).to eq([second, [second, first]])
  end

  it "names the disk something else put in" do
    media.insert(:disk, first)
    Badline::Media.attach(computer, second, autostart: false)
    expect(media.disk_path).to eq(second)
  end

  it "names no disk once something else took it out" do
    media.insert(:disk, first)
    computer.unmount
    expect(media.disk_path).to eq("")
  end

  it "names the disk a restored snapshot put back" do
    media.insert(:disk, first)
    computer.save_snapshot(File.join(dir, "first.vsf"))
    media.insert(:disk, second)
    computer.restore_snapshot(File.join(dir, "first.vsf"))
    expect(media.disk_path).to eq(first)
  end

  it "steps from the disk in a true drive through its set" do
    second
    Badline::Media::TrueDrive.insert(computer, first)
    media.drive(:next_disk)
    expect(media.disk_path).to eq(second)
  end

  it "keeps what went wrong with a list" do
    File.write(File.join(dir, "game.m3u"), "missing.d64\n")
    media.insert(:disk, File.join(dir, "game.m3u"))
    expect(media.problem).to include("no disk image")
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

  it "names a save after the disk, without its bracketed parts" do
    media.insert(:disk, blank_d64(File.join(dir, "Ninja (1987)(Disk 1 of 2).d64")))
    expect(media.game_name).to eq("Ninja")
  end

  it "names a save after the cartridge" do
    media.attach_cartridge(crt("game.crt"))
    expect(media.game_name).to eq("GAME")
  end

  it "names a save BASIC with nothing attached" do
    expect(media.game_name).to eq("BASIC")
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
    started = start_quietly(first)
    media.computer = started
    expect([started.equal?(computer), started.mounted?, media.disk_path]).to eq([false, true, first])
  end

  it "says what it put in the new machine" do
    expect { media.start(Badline::Options.parse([]), first) }.to output(/Mounted .*disk1\.d64 as device 8/).to_stdout
  end

  it "starts nothing from a file it can't read" do
    File.write(File.join(dir, "bad.crt"), "junk")
    expect(media.start(Badline::Options.parse([]), File.join(dir, "bad.crt"))).to be_nil
  end

  it "keeps the problem with a .t64, which doesn't go in as a disk" do
    tape = File.join(dir, "game.t64")
    File.binwrite(tape, "junk")
    expect([media.insert(:disk, tape), media.problem]).to eq([false, "#{tape} is not a disk image or a directory"])
  end

  describe "on a PET" do
    let(:computer) { Badline::PET.new(model: "3032") }

    it "takes no cartridges" do
      expect(media.cartridge_extensions).to eq([])
    end

    it "lists the 8050's and 8250's disks for device 8" do
      expect(media.disk_extensions).to include(".d80", ".d82", ".d64")
    end

    it "lists no raw GCR for device 8" do
      expect(media.disk_extensions).not_to include(".g64")
    end

    it "names a save after BASIC with nothing in" do
      expect(media.game_name).to eq("BASIC")
    end

    it "names no cartridge" do
      expect(media.cartridge_name).to eq("")
    end
  end

  describe "on a CBM-II" do
    let(:computer) { Badline::CBM2.new }

    it "takes no cartridges from the menu" do
      expect(media.cartridge_extensions).to eq([])
    end

    it "lists the 8050's and 8250's disks for device 8" do
      expect(media.disk_extensions).to include(".d80", ".d82", ".d64")
    end

    it "names a save after BASIC with nothing in" do
      expect(media.game_name).to eq("BASIC")
    end

    it "keeps the problem with a tape, having no datasette" do
      expect([media.insert(:tape, "game.tap"), media.problem]).to eq([false, "the CBM-II has no datasette"])
    end
  end

  describe "on a KIM-1" do
    let(:computer) { Badline::KIM1.new }

    it "lists .wav files as tapes" do
      expect(media.tape_extensions).to eq(%w[.wav])
    end

    it "puts a tape in the deck" do
      path = File.join(dir, "dump.wav")
      Badline::Storage::KIMTape.new(crossings: [100, 235, 370]).write_wav(path)
      media.insert(:tape, path)
      expect(computer.tape.tape.path).to eq(path)
    end

    it "keeps the problem with a file that isn't a WAVE" do
      path = File.join(dir, "game.wav")
      File.binwrite(path, "junk")
      expect([media.insert(:tape, path), media.problem]).to eq([false, "Not a RIFF WAVE file"])
    end

    it "keeps the problem with a disk" do
      expect([media.insert(:disk, "game.d64"), media.problem]).to eq([false, "the KIM-1 takes no disks"])
    end
  end

  describe "on a Plus/4" do
    let(:computer) { Badline::Plus4.new }

    it "takes raw ROM images as cartridges" do
      expect(media.cartridge_extensions).to eq(%w[.crt .bin])
    end

    it "names a save after the disk, not the cartridge slots" do
      computer.attach_cartridge([Badline::Storage::CRTFile::Chip.new(0, 0, 0x8000, [0x11])])
      media.insert(:disk, first)
      expect(media.game_name).to eq("game disk1")
    end

    it "puts a ROM image in cartridge 1" do
      path = File.join(dir, "game.bin").tap { |file| File.binwrite(file, "\x11" * 16) }
      media.attach_cartridge(path)
      expect(computer.cartridge_slots).to eq(%w[c1lo])
    end

    it "keeps the problem with a .crt chip in a bank it doesn't map" do
      attached = media.attach_cartridge(plus4_crt(bank: 2))
      expect([attached, media.problem]).to eq([false, "no Plus/4 cartridge slot in bank 2"])
    end

    it "starts nothing from a .crt chip in a bank it doesn't map" do
      expect(media.start(Badline::Options.parse(["plus4"]), plus4_crt(bank: 2))).to be_nil
    end

    it "names a ROM image after its file" do
      media.attach_cartridge(rom_image("game.bin", 0x8000))
      expect(media.cartridge_name).to eq("game")
    end

    it "names each cartridge after its .crt's own name" do
      media.attach_cartridge(named_crt("game", "c1lo"))
      media.attach_cartridge(named_crt("tool", "c2hi"))
      expect(media.cartridge_name).to eq("GAME, TOOL")
    end

    it "names the ROM images the command line put in their slots" do
      path = rom_image("tool.bin", 0x4000)
      Badline::Media.attach(computer, path, cartridge: { slot: "c2lo" })
      media = described_class.new("", false, { "c2lo" => path }).tap { |menu_media| menu_media.computer = computer }
      expect(media.cartridge_name).to eq("tool")
    end

    it "names a cartridge Quick open started" do
      media.computer = quietly { media.start(Badline::Options.parse(["plus4"]), rom_image("game.bin", 0x4000)) }
      expect(media.cartridge_name).to eq("game")
    end

    it "keeps the problem with a ROM image too large for a slot" do
      path = File.join(dir, "game.bin").tap { |file| File.binwrite(file, "\x11" * 0x8001) }
      expect([media.attach_cartridge(path), media.problem]).to eq([false, "a 32769-byte image is no Plus/4 cartridge"])
    end
  end

  describe "on a C128" do
    let(:computer) { Badline::C128.new }

    it "names the cartridge after its .crt's own name" do
      media.attach_cartridge(crt("game.crt"))
      expect(media.cartridge_name).to eq("GAME")
    end
  end

  describe "on a VIC-20" do
    let(:computer) { Badline::Vic20.new }

    it "mounts a disk on device 8" do
      media.insert(:disk, first)
      expect(computer.mounted?).to be(true)
    end

    it "names the disk something else put in" do
      media.insert(:disk, first)
      Badline::Media.attach(computer, second, autostart: false)
      expect(media.disk_path).to eq(second)
    end

    it "names a save after the machine without a disk" do
      expect(media.game_name).to eq("VIC-20")
    end

    it "names a .crt after its own name" do
      path = File.join(dir, "game.crt")
      header = "VIC20 CARTRIDGE ".b + [0x40, 0x0100, 0, 0, 0].pack("NnnCC") + ("\x00" * 6) + "GAME".ljust(32, "\x00")
      File.binwrite(path, header + "CHIP".b + [0x2010, 0, 0, 0xa000, 0x2000].pack("Nn4") + ("\x42" * 0x2000))
      media.attach_cartridge(path)
      expect(media.cartridge_name).to eq("GAME")
    end

    it "names the cartridge the command line started after its file" do
      path = File.join(dir, "game.a0").tap { |file| File.binwrite(file, "\x00\xa0".b + ("\x42" * 0x1000)) }
      Badline::Media.attach(computer, path)
      media = described_class.new(path, false, {}).tap { |menu_media| menu_media.computer = computer }
      expect(media.cartridge_name).to eq("game")
    end

    it "names the cartridge of a machine restored from a snapshot" do
      path = File.join(dir, "game.a0").tap { |file| File.binwrite(file, "\x00\xa0".b + ("\x42" * 0x1000)) }
      media.attach_cartridge(path)
      media.computer = computer.snapshot.load
      expect(media.cartridge_name).to eq("game")
    end

    it "names no cartridge on another machine than the one it named" do
      path = File.join(dir, "game.a0").tap { |file| File.binwrite(file, "\x00\xa0".b + ("\x42" * 0x1000)) }
      media = described_class.new(path, false, {}).tap { |menu_media| menu_media.computer = computer }
      media.computer = Badline::Vic20.new
      expect(media.cartridge_name).to eq("")
    end

    it "puts a tape in the datasette" do
      File.binwrite(File.join(dir, "game.tap"), "C64-TAPE-RAW".b + [1, 0, 0, 0, 1].pack("C4V") + "\x30".b)
      media.insert(:tape, File.join(dir, "game.tap"))
      expect(computer.datasette.tape).not_to be_nil
    end
  end
end
