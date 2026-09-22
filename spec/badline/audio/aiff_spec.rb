# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Audio::AIFF do
  subject(:bytes) { File.binread(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "out.aiff") }
  let(:rate) { 8000 }

  before do
    described_class.open(path, rate:) { |aiff| [1, -2, 3].each { |s| aiff << s } }
  end

  after { FileUtils.remove_entry(dir) }

  it "tags the chunks" do
    expect([bytes[0, 4], bytes[8, 4], bytes[12, 4], bytes[38, 4]])
      .to eq(%w[FORM AIFF COMM SSND])
  end

  it "declares one channel" do
    expect(bytes[20, 2].unpack1("n")).to eq(1)
  end

  it "declares 16 bits per sample" do
    expect(bytes[26, 2].unpack1("n")).to eq(16)
  end

  it "stores the sample rate as an 80-bit extended float" do
    expect(bytes[28, 10].unpack1("H*")).to eq("400bfa00000000000000")
  end

  context "with the CD sample rate" do
    let(:rate) { 44_100 }

    it "stores the sample rate as an 80-bit extended float" do
      expect(bytes[28, 10].unpack1("H*")).to eq("400eac44000000000000")
    end
  end

  it "patches the FORM size once the stream ends" do
    expect(bytes[4, 4].unpack1("N")).to eq(52)
  end

  it "patches the frame count once the stream ends" do
    expect(bytes[22, 4].unpack1("N")).to eq(3)
  end

  it "patches the SSND size once the stream ends" do
    expect(bytes[42, 4].unpack1("N")).to eq(14)
  end

  it "writes big-endian samples" do
    expect(bytes[54..].unpack("s>*")).to eq([1, -2, 3])
  end
end
