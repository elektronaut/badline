# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::HostDirectory do
  subject(:storage) { described_class.new(dir) }

  let(:dir) { Dir.mktmpdir }

  before do
    File.binwrite(File.join(dir, "HELLO.PRG"), [0x01, 0x08, 0x60].pack("C*"))
    File.binwrite(File.join(dir, "intro.prg"), [0x00, 0xc0, 0xaa].pack("C*"))
    File.binwrite(File.join(dir, "notes.txt"), "not a program")
    File.binwrite(File.join(dir, "zz-game.p00"),
                  "C64File\x00LONG NAME#{"\x00" * 9}".b + [0x00, 0x20, 0x77].pack("C*"))
    File.binwrite(File.join(dir, "zz-fake.p00"), "not a container")
    File.binwrite(File.join(dir, "zz-tape.t64"), t64_archive)
    File.binwrite(File.join(dir, "zz-junk.t64"), "not an archive")
  end

  after { FileUtils.remove_entry(dir) }

  # Two normal entries: MUSIC at $0801 and LOADER at $c000.
  def t64_archive
    bytes = Array.new(0x40 + (2 * 32), 0)
    bytes[0, 32] = "C64S tape image file".bytes + ([0x20] * 12)
    bytes[0x22, 2] = [2, 0]
    bytes[0x24, 2] = [2, 0]
    bytes[0x40, 32] = t64_entry("MUSIC", 0x0801, 3, 0x80)
    bytes[0x60, 32] = t64_entry("LOADER", 0xc000, 2, 0x83)
    (bytes + [0xaa, 0xbb, 0xcc, 0x11, 0x22]).pack("C*")
  end

  def t64_entry(name, load, size, offset)
    entry = Array.new(32, 0)
    entry[0] = 1
    entry[2, 4] = [load, load + size].pack("v2").bytes
    entry[8, 4] = [offset].pack("V").bytes
    entry[16, 16] = name.bytes + ([0x20] * (16 - name.length))
    entry
  end

  describe "#read_file" do
    it "reads a file as bytes" do
      expect(storage.read_file("INTRO")).to eq([0x00, 0xc0, 0xaa])
    end

    it "matches names case-insensitively" do
      expect(storage.read_file("hello")).to eq([0x01, 0x08, 0x60])
    end

    it "returns the first file for a bare wildcard" do
      expect(storage.read_file("*")).to eq([0x01, 0x08, 0x60])
    end

    it "matches a name with a trailing wildcard" do
      expect(storage.read_file("IN*")).to eq([0x00, 0xc0, 0xaa])
    end

    it "matches ? as a single character" do
      expect(storage.read_file("HEL?O")).to eq([0x01, 0x08, 0x60])
    end

    it "returns nil for an unknown name" do
      expect(storage.read_file("MISSING")).to be_nil
    end

    it "ignores files without a .prg extension" do
      expect(storage.read_file("NOTES")).to be_nil
    end

    it "serves a .p00 by its embedded name, header stripped" do
      expect(storage.read_file("long name")).to eq([0x00, 0x20, 0x77])
    end

    it "ignores .p00 files without the magic" do
      expect(storage.read_file("zz-fake")).to be_nil
    end

    it "serves a .t64 entry by its embedded name" do
      expect(storage.read_file("music")).to eq([0x01, 0x08, 0xaa, 0xbb, 0xcc])
    end

    it "serves every entry in a .t64" do
      expect(storage.read_file("LOADER")).to eq([0x00, 0xc0, 0x11, 0x22])
    end

    it "matches .t64 entries with wildcards" do
      expect(storage.read_file("LOAD*")).to eq([0x00, 0xc0, 0x11, 0x22])
    end

    it "does not serve a .t64 by its host filename" do
      expect(storage.read_file("zz-tape")).to be_nil
    end

    it "ignores .t64 files without the signature" do
      expect(storage.read_file("zz-junk")).to be_nil
    end
  end

  describe "#read_file with files the host can't read" do
    after { File.chmod(0o755, dir) }

    it "returns nil for an unreadable .prg" do
      File.chmod(0o000, File.join(dir, "intro.prg"))
      expect(storage.read_file("INTRO")).to be_nil
    end

    it "serves the other files past an unreadable .p00" do
      File.chmod(0o000, File.join(dir, "zz-game.p00"))
      expect(storage.read_file("LOADER")).to eq([0x00, 0xc0, 0x11, 0x22])
    end

    it "skips an unreadable .t64" do
      File.chmod(0o000, File.join(dir, "zz-tape.t64"))
      expect(storage.read_file("MUSIC")).to be_nil
    end

    it "returns nil when the directory can't be listed" do
      File.chmod(0o000, dir)
      expect(storage.read_file("INTRO")).to be_nil
    end

    it "returns nil when the directory is gone" do
      expect(described_class.new(File.join(dir, "gone")).read_file("INTRO")).to be_nil
    end
  end

  describe "#write_file" do
    before { storage.write_file("NEW GAME", [0x00, 0xc0, 0x42]) }

    it "writes a .prg file with a lowercased name" do
      expect(File.binread(File.join(dir, "new game.prg")).bytes).to eq([0x00, 0xc0, 0x42])
    end

    it "serves the written file back" do
      expect(storage.read_file("NEW GAME")).to eq([0x00, 0xc0, 0x42])
    end

    it "overwrites an existing file" do
      storage.write_file("INTRO", [0x00, 0x10, 0x99])
      expect(storage.read_file("INTRO")).to eq([0x00, 0x10, 0x99])
    end

    it "keeps path separators out of the host filename" do
      storage.write_file("A/B", [0x01])
      expect(File.binread(File.join(dir, "a_b.prg")).bytes).to eq([0x01])
    end

    it "reports the write" do
      expect(storage.write_file("MORE", [0x01])).to be(true)
    end
  end

  describe "#write_file when the host can't write" do
    it "reports a failure for a read-only directory" do
      File.chmod(0o555, dir)
      expect(storage.write_file("NEW GAME", [0x01])).to be(false)
    ensure
      File.chmod(0o755, dir)
    end

    it "reports a failure for a directory in the way" do
      Dir.mkdir(File.join(dir, "new game.prg"))
      expect(storage.write_file("NEW GAME", [0x01])).to be(false)
    end

    it "reports a failure for a full disk" do
      allow(File).to receive(:binwrite).and_raise(Errno::ENOSPC)
      expect(storage.write_file("NEW GAME", [0x01])).to be(false)
    end
  end
end
