# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Audio::BarePlayer do
  subject(:player) { described_class.new(tune).tap(&:start) }

  let(:dir) { Dir.mktmpdir }
  let(:tune) { Badline::Storage::SIDFile.new(path) }
  let(:speed) { 0 }
  let(:timer) { [] }
  let(:flags) { 0x04 }

  before { File.binwrite(path, (header + image).pack("C*")) }
  after { FileUtils.remove_entry(dir) }

  def path = File.join(dir, "tune.sid")

  # init runs whatever `timer` holds; play is an RTS.
  def image
    init = timer + [0x60]
    init + ([0xea] * (0x10 - init.length)) + [0x60]
  end

  def header
    fields = { version: 2, data_offset: 0x7c, load: 0x1000, init: 0x1000,
               play: 0x1010, songs: 1, start_song: 1 }
    words = fields.values.flat_map { |value| [value >> 8, value & 0xff] }
    "PSID".bytes + words + [speed >> 24, (speed >> 16) & 0xff, (speed >> 8) & 0xff, speed & 0xff] +
      ([0] * 96) + [0x00, flags, 0x00, 0x01, 0x00, 0x00]
  end

  describe "#frame" do
    it "calls play once a PAL frame" do
      expect(player.frame(100_000) { nil }).to eq(described_class::FRAME_CYCLES)
    end

    it "stops short when the budget does" do
      expect(player.frame(100) { nil }).to eq(100)
    end

    context "with a CIA-timed song" do
      let(:speed) { 1 }

      it "calls play at the rate the KERNAL leaves timer A running at" do
        expect(player.frame(100_000) { nil }).to eq(described_class::KERNAL_TIMER + 1)
      end
    end

    context "with a CIA-timed song whose init sets timer A" do
      let(:speed) { 1 }
      let(:timer) { [0xa9, 0x00, 0x8d, 0x04, 0xdc, 0xa9, 0x10, 0x8d, 0x05, 0xdc] }

      it "calls play once a timer period" do
        expect(player.frame(100_000) { nil }).to eq(0x1001)
      end
    end

    context "with an NTSC tune" do
      let(:flags) { 0x08 }

      it "calls play once an NTSC frame" do
        expect(player.frame(100_000) { nil }).to eq(described_class::NTSC_FRAME_CYCLES)
      end
    end

    context "with a CIA-timed NTSC tune" do
      let(:speed) { 1 }
      let(:flags) { 0x08 }

      it "calls play at the rate the NTSC KERNAL leaves timer A running at" do
        expect(player.frame(100_000) { nil }).to eq(described_class::NTSC_KERNAL_TIMER + 1)
      end
    end
  end

  describe "the video standard" do
    def peek_flag = player.instance_variable_get(:@bus).peek(0x02a6)

    it "tells a PAL tune it runs on PAL" do
      expect([peek_flag, player.clock_hz]).to eq([1, 985_248])
    end

    context "with an NTSC tune" do
      let(:flags) { 0x08 }

      it "tells it it runs on NTSC" do
        expect([peek_flag, player.clock_hz]).to eq([0, 1_022_727])
      end
    end
  end
end
