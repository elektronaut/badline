# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Audio::WAV do
  subject(:bytes) { File.binread(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "out.wav") }
  let(:written) { [1, -2, 3] }

  before do
    described_class.open(path, rate: 8000) { |wav| written.each { |s| wav << s } }
  end

  after { FileUtils.remove_entry(dir) }

  it "tags the chunks" do
    expect([bytes[0, 4], bytes[8, 4], bytes[12, 4], bytes[36, 4]])
      .to eq(["RIFF", "WAVE", "fmt ", "data"])
  end

  it "declares uncompressed PCM" do
    expect(bytes[20, 2].unpack1("v")).to eq(1)
  end

  it "declares one channel" do
    expect(bytes[22, 2].unpack1("v")).to eq(1)
  end

  it "declares the sample rate" do
    expect(bytes[24, 4].unpack1("V")).to eq(8000)
  end

  it "declares the byte rate" do
    expect(bytes[28, 4].unpack1("V")).to eq(16_000)
  end

  it "declares 16 bits per sample" do
    expect(bytes[34, 2].unpack1("v")).to eq(16)
  end

  it "patches the RIFF size once the stream ends" do
    expect(bytes[4, 4].unpack1("V")).to eq(42)
  end

  it "patches the data size once the stream ends" do
    expect(bytes[40, 4].unpack1("V")).to eq(6)
  end

  it "writes little-endian samples" do
    expect(bytes[44..].unpack("s<*")).to eq([1, -2, 3])
  end

  context "with more samples than the buffer holds" do
    let(:written) { Array.new(described_class::BUFFER + 1, 7) }

    it "patches the size across the flushes" do
      expect(bytes[40, 4].unpack1("V")).to eq(written.length * 2)
    end
  end
end
