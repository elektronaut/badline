# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::SIDFile do
  subject(:tune) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:speed) { 0 }
  let(:start_page) { 0 }
  let(:image) { [0xa9, 0x00] + ([0xea] * 0x1d) + [0x60] }
  let(:fields) do
    { version: 2, data_offset: 0x7c, load: 0x1000,
      init: 0x1000, play: 0x1020, songs: 2, start_song: 1 }
  end

  before { File.binwrite(path, (header + image).pack("C*")) }
  after { FileUtils.remove_entry(dir) }

  def path
    File.join(dir, "tune.sid")
  end

  def header
    words = fields.values.flat_map { |value| [value >> 8, value & 0xff] }
    base = "PSID".bytes + words + [speed].pack("N").bytes + texts
    return base unless fields[:version] > 1

    base + [0x00, 0x04, start_page, 0x01, 0x00, 0x00]
  end

  def texts
    %w[TUNE AUTHOR 1987].flat_map { |text| text.bytes + ([0] * (32 - text.length)) }
  end

  # The jmp over the IRQ handler and the handler itself precede the boot stub.
  def handler
    tune.driver[3, 21]
  end

  def boot
    tune.driver.drop(24)
  end

  # lda $01 / pha / lda #bank / sta $01
  def bank(value)
    [0xa5, 0x01, 0x48, 0xa9, value, 0x85, 0x01]
  end

  # pla / sta $01
  def unbank
    [0x68, 0x85, 0x01]
  end

  describe "the header" do
    it "reads the format" do
      expect(tune.format).to eq("PSID")
    end

    it "reads big-endian words" do
      expect(tune.load_address).to eq(0x1000)
    end

    it "reads the init address" do
      expect(tune.init_address).to eq(0x1000)
    end

    it "reads the play address" do
      expect(tune.play_address).to eq(0x1020)
    end

    it "reads the song count" do
      expect(tune.songs).to eq(2)
    end

    it "reads the name" do
      expect(tune.name).to eq("TUNE")
    end

    it "reads the author" do
      expect(tune.author).to eq("AUTHOR")
    end

    it "reads the release" do
      expect(tune.released).to eq("1987")
    end

    it "reads the v2 flags" do
      expect(tune.flags).to eq(0x04)
    end

    it "takes the data from the data offset" do
      expect(tune.data).to eq(image)
    end

    it "reports the end address" do
      expect(tune.end_address).to eq(0x1000 + image.length)
    end
  end

  describe "#init_address" do
    let(:fields) { super().merge(init: 0) }

    it "falls back to the load address" do
      expect(tune.init_address).to eq(0x1000)
    end
  end

  describe "#start_song" do
    let(:fields) { super().merge(start_song: 9) }

    it "clamps to the song count" do
      expect(tune.start_song).to eq(2)
    end
  end

  describe "#cia_timed?" do
    let(:speed) { 0b10 }

    it "is false for a raster-paced song" do
      expect(tune.cia_timed?(1)).to be(false)
    end

    it "is true for a song whose speed bit is set" do
      expect(tune.cia_timed?(2)).to be(true)
    end
  end

  describe "a version 1 header" do
    let(:fields) { super().merge(version: 1, data_offset: 0x76) }

    it "has no flags" do
      expect(tune.flags).to eq(0)
    end

    it "still finds the data" do
      expect(tune.data).to eq(image)
    end
  end

  describe "an embedded load address" do
    let(:fields) { super().merge(load: 0) }
    let(:image) { [0x00, 0x20, 0xa9, 0x00, 0x60] }

    it "takes the load address from the data" do
      expect(tune.load_address).to eq(0x2000)
    end

    it "strips it from the data" do
      expect(tune.data).to eq([0xa9, 0x00, 0x60])
    end
  end

  describe "#driver_address" do
    it "defaults to the tape buffer" do
      expect(tune.driver_address).to eq(0x0334)
    end

    context "when the header names a relocation page" do
      let(:start_page) { 0xc8 }

      it "uses it" do
        expect(tune.driver_address).to eq(0xc800)
      end
    end

    context "when the header rules relocation out" do
      let(:start_page) { 0xff }

      it "falls back to the tape buffer" do
        expect(tune.driver_address).to eq(0x0334)
      end
    end

    context "when the tune covers the tape buffer" do
      let(:fields) { super().merge(load: 0x0300) }
      let(:image) { [0xea] * 0x100 }

      it "falls back to the block below the stack page" do
        expect(tune.driver_address).to eq(0x02a7)
      end
    end

    context "when the tune covers every candidate" do
      let(:fields) { super().merge(load: 0x0200) }
      let(:image) { [0xea] * 0x400 }

      it "raises" do
        expect { tune.driver_address }.to raise_error(described_class::FormatError)
      end
    end
  end

  describe "#driver" do
    it "jumps over the IRQ handler" do
      expect(tune.driver[0, 3]).to eq([0x4c, 0x4c, 0x03])
    end

    it "acknowledges the raster IRQ before calling play" do
      expect(handler[0, 5]).to eq([0xa9, 0x01, 0x8d, 0x19, 0xd0])
    end

    it "banks the tune in for play" do
      expect(handler[5, 7]).to eq(bank(0x37))
    end

    it "calls play" do
      expect(handler[12, 3]).to eq([0x20, 0x20, 0x10])
    end

    it "restores the caller's banking after play" do
      expect(handler[15, 3]).to eq(unbank)
    end

    it "chains into the KERNAL IRQ handler" do
      expect(handler.last(3)).to eq([0x4c, 0x31, 0xea])
    end

    it "disables interrupts before init" do
      expect(boot[0]).to eq(0x78)
    end

    it "banks the tune in for init" do
      expect(boot[1, 7]).to eq(bank(0x37))
    end

    it "passes the song index in A" do
      expect(boot[8, 2]).to eq([0xa9, 0x00])
    end

    it "calls init" do
      expect(boot[10, 3]).to eq([0x20, 0x00, 0x10])
    end

    it "restores the caller's banking after init" do
      expect(boot[13, 3]).to eq(unbank)
    end

    it "masks the CIA 1 interrupts" do
      expect(boot.each_cons(5).to_a).to include([0xa9, 0x7f, 0x8d, 0x0d, 0xdc])
    end

    it "enables the raster IRQ" do
      expect(boot.each_cons(3).to_a).to include([0x8d, 0x1a, 0xd0])
    end

    it "points the KERNAL IRQ vector at the handler" do
      expect(boot.each_cons(5).to_a).to include([0xa9, 0x37, 0x8d, 0x14, 0x03])
    end

    it "returns to the caller with interrupts enabled" do
      expect(boot.last(2)).to eq([0x58, 0x60])
    end

    it "passes the requested song" do
      expect(tune.driver(song: 2)[32, 2]).to eq([0xa9, 0x01])
    end

    it "clamps the requested song" do
      expect(tune.driver(song: 7)[32, 2]).to eq([0xa9, 0x01])
    end
  end

  describe "#driver for a tune under BASIC" do
    let(:fields) { super().merge(load: 0xa000, init: 0xa000, play: 0xa020) }

    it "banks BASIC out for init" do
      expect(boot[1, 7]).to eq(bank(0x36))
    end

    it "banks BASIC out for play" do
      expect(handler[5, 7]).to eq(bank(0x36))
    end
  end

  describe "#bank_for" do
    it "leaves the ROMs in place below $a000" do
      expect(tune.bank_for(0x9fff)).to eq(0x37)
    end

    it "banks BASIC out" do
      expect(tune.bank_for(0xa000)).to eq(0x36)
    end

    it "banks the I/O window out" do
      expect(tune.bank_for(0xd000)).to eq(0x34)
    end

    it "banks the KERNAL out" do
      expect(tune.bank_for(0xe000)).to eq(0x35)
    end

    context "with an RSID tune" do
      before { File.binwrite(path, (header + image).pack("C*").sub("PSID", "RSID")) }

      it "leaves the banking to the tune" do
        expect(tune.bank_for(0xa000)).to be_nil
      end
    end
  end

  describe "#md5" do
    it "digests the whole file" do
      expect(tune.md5).to eq(Digest::MD5.file(path).hexdigest)
    end
  end

  describe "#driver for an RSID tune" do
    before { File.binwrite(path, (header + image).pack("C*").sub("PSID", "RSID")) }

    it "leaves the banking to the tune" do
      expect(handler[5, 3]).to eq([0x20, 0x20, 0x10])
    end
  end

  describe "#driver without a play address" do
    let(:fields) { super().merge(play: 0) }

    it "only calls init" do
      expect(tune.driver)
        .to eq([0x78] + bank(0x37) + [0xa9, 0x00, 0x20, 0x00, 0x10] + unbank + [0x58, 0x60])
    end
  end

  describe ".new" do
    it "rejects a file without a PSID or RSID signature" do
      File.binwrite(path, "NOPE" * 64)
      expect { tune }.to raise_error(described_class::FormatError, /signature/)
    end

    it "rejects a truncated header" do
      File.binwrite(path, "PSID#{"\x00" * 16}")
      expect { tune }.to raise_error(described_class::FormatError, /Truncated/)
    end

    it "rejects a file with no tune data" do
      File.binwrite(path, header.pack("C*"))
      expect { tune }.to raise_error(described_class::FormatError, /No tune data/)
    end

    it "accepts an RSID signature" do
      File.binwrite(path, (header + image).pack("C*").sub("PSID", "RSID"))
      expect(tune.format).to eq("RSID")
    end
  end
end
