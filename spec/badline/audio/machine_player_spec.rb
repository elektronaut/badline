# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Audio::MachinePlayer do
  subject(:player) { described_class.new(tune) }

  let(:dir) { Dir.mktmpdir }
  let(:tune) { Badline::Storage::SIDFile.new(path) }

  before { File.binwrite(path, (header + image).pack("C*")) }
  after { FileUtils.remove_entry(dir) }

  def path = File.join(dir, "tune.sid")

  # init stores $42 at $fb and play counts calls in $fc, so zero page
  # shows which of them ran.
  def image
    init = [0xa9, 0x42, 0x85, 0xfb, 0x60]
    init + ([0xea] * (0x10 - init.length)) + [0xe6, 0xfc, 0x60]
  end

  def header
    fields = { version: 2, data_offset: 0x7c, load: 0x1000, init: 0x1000,
               play: 0x1010, songs: 1, start_song: 1 }
    words = fields.values.flat_map { |value| [value >> 8, value & 0xff] }
    "PSID".bytes + words + ([0] * 4) + ([0] * 96) +
      [0x00, 0x04, 0x00, 0x01, 0x00, 0x00]
  end

  def count_frame(budget)
    samples = 0
    cycles = player.frame(budget) { samples += 1 }
    [cycles, samples]
  end

  describe "#frame" do
    it "advances a whole PAL frame" do
      expect(count_frame(described_class::FRAME_CYCLES * 2).first)
        .to eq(described_class::FRAME_CYCLES)
    end

    it "stops short when the budget does" do
      expect(count_frame(100).first).to eq(100)
    end

    it "yields one sample per cycle" do
      expect(count_frame(100).last).to eq(100)
    end
  end

  # A real boot takes ~2.5M cycles, so this runs only with --tag slow.
  describe "#start", :slow do
    let(:computer) { Badline::Computer.new }

    before { allow(Badline::Computer).to receive(:new).and_return(computer) }

    def peek(addr) = computer.address_bus.peek(addr)
    def screen = Array.new(1000) { |i| peek(0x0400 + i) }
    def ready? = screen.each_cons(6).include?([0x12, 0x05, 0x01, 0x04, 0x19, 0x2e])

    def state
      { ready: ready?, init: peek(0xfb), vector: peek(0x0314) | (peek(0x0315) << 8),
        played: peek(0xfc).positive? }
    end

    def play_after_start
      player.start
      started = { synthesizing: player.sid.synthesizing? }
      2.times { player.frame(described_class::FRAME_CYCLES) { nil } }
      started.merge(state)
    end

    it "boots and starts synthesis at the driver, which then runs init and play" do
      expect(play_after_start).to eq(synthesizing: true, ready: true, init: 0x42,
                                     vector: tune.driver_address + 3, played: true)
    end
  end
end
