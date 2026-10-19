# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../support/kim_tape_signal"

# The tones and the bits are the KIM-1 User Manual's appendix E: each bit
# 3,700 Hz then 2,400 Hz, a 1 with the change a third of the way in and a
# 0 two thirds of the way.
describe Badline::Storage::KIMTape do
  let(:chars) { KIMTapeSignal.block(0x01, 0x0200, [0xa9, 0x42]) }
  let(:crossings) { KIMTapeSignal.crossings(chars) }

  # The characters a tape of `wav_bytes` plays to LOADT, but the last,
  # whose last bit no edge ends.
  def played(wav_bytes)
    edges = described_class.new(crossings: described_class.from_wav(wav_bytes)).edges
    KIMTapeSignal.characters(edges)
  end

  def wav(rate: 22_050, bits: 8, channels: 1, **signal)
    KIMTapeSignal.wav(KIMTapeSignal.samples(crossings, rate:, **signal), rate:, bits:, channels:)
  end

  def after_leader(chars) = chars.drop_while { |char| char == 0x16 }

  describe "#edges" do
    it "holds PB7 low through the high tone and high through the low tone" do
      tape = described_class.new(crossings: [0, 135, 270, 405, 540, 748, 956, 1164, 1372])
      expect(tape.edges).to eq([67, 472])
    end

    it "leaves PB7 alone for a crossing out of place" do
      tape = described_class.new(crossings: [0, 208, 416, 540, 832, 1040, 1248])
      expect(tape.edges).to eq([])
    end

    it "gives LOADT the bits of a block" do
      expect(KIMTapeSignal.characters(described_class.new(crossings:).edges)).to eq(chars[0..-2])
    end

    it "gives LOADT the bits at DUMPT's speed too" do
      tape = described_class.new(crossings: KIMTapeSignal.crossings(chars, speed: KIMTapeSignal::ROM_SPEED))
      expect(KIMTapeSignal.characters(tape.edges)).to eq(chars[0..-2])
    end
  end

  describe ".from_wav" do
    it "reads an 8-bit recording at 22,050 Hz" do
      expect(played(wav)).to eq(chars[0..-2])
    end

    it "reads the first channel of a 16-bit stereo recording" do
      expect(played(wav(bits: 16, channels: 2))).to eq(chars[0..-2])
    end

    it "follows a recording off centre, quiet and noisy" do
      expect(after_leader(played(wav(gain: 0.1, offset: 0.3, noise: 0.03)))).to eq(after_leader(chars[0..-2]))
    end

    it "times each crossing to within a quarter of a sample" do
      first = crossings.first(400)
      found = described_class.from_wav(KIMTapeSignal.wav(KIMTapeSignal.samples(first, rate: 44_100), rate: 44_100))
      expect(found.zip(first).map { |(at, want)| (at - want).abs }.max).to be <= 5
    end

    it "refuses a file that isn't a WAVE" do
      expect { described_class.from_wav("RIFF....AVI ".bytes) }.to raise_error(described_class::FormatError)
    end

    it "refuses PCM of other widths" do
      bytes = wav
      bytes[34] = 24
      expect { described_class.from_wav(bytes) }.to raise_error(described_class::FormatError, /8-bit and 16-bit/)
    end
  end

  describe "recording" do
    subject(:tape) { described_class.new(crossings: [100, 200, 300, 400]) }

    it "erases the tape from where it records" do
      tape.truncate(300)
      tape.record(350)
      expect(tape.crossings).to eq([100, 200, 350])
    end

    it "is as long as its last crossing" do
      expect(tape.length).to eq(400)
    end
  end

  describe "#write" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "block.wav") }

    after { FileUtils.remove_entry(dir) }

    it "writes a square wave that reads back" do
      described_class.new(crossings:).write(path)
      expect(KIMTapeSignal.characters(described_class.read(path).edges)).to eq(chars[0..-2])
    end

    it "writes 16-bit PCM" do
      described_class.new(crossings:).write(path, rate: 22_050, bits: 16)
      expect(File.binread(path, 4, 32).unpack("vv")).to eq([2, 16])
    end

    it "creates a blank tape at a path" do
      tape = described_class.create(path)
      expect([tape.path, described_class.read(path).crossings]).to eq([path, []])
    end
  end
end
