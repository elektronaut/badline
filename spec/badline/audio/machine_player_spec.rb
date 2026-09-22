# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Booting the machine takes millions of cycles, so #start is left to the
# renderer; what is cheap to pin here is the frame pacing.
describe Badline::Audio::MachinePlayer do
  subject(:player) { described_class.new(tune) }

  let(:dir) { Dir.mktmpdir }
  let(:tune) { Badline::Storage::SIDFile.new(path) }

  before { File.binwrite(path, (header + [0xa9, 0x00, 0x60]).pack("C*")) }
  after { FileUtils.remove_entry(dir) }

  def path = File.join(dir, "tune.sid")

  def header
    fields = { version: 2, data_offset: 0x7c, load: 0x1000, init: 0x1000,
               play: 0x1000, songs: 1, start_song: 1 }
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
end
