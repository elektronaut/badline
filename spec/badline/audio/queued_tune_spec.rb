# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/tiny_sid"

describe Badline::Audio::QueuedTune do
  subject(:entry) { described_class.new(path, options, subtune:) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "tune.sid") }
  let(:options) { Badline::Options.parse(["sid", *arguments, path]) }
  let(:arguments) { [] }
  let(:subtune) { nil }

  before { File.binwrite(path, TinySID.bytes(flags: 0x24)) }
  after { FileUtils.remove_entry(dir) }

  it "starts on the tune's own subtune, out of its subtunes" do
    expect([entry.part, entry.parts, entry.error]).to eq([1, 2, ""])
  end

  it "fits the SID the tune names" do
    expect(entry.model_name).to eq("8580")
  end

  it "reads the header" do
    expect(entry.header).to eq(%w[TUNE AUTHOR 1987])
  end

  context "with a subtune asked for" do
    let(:subtune) { 2 }

    it "starts on it" do
      expect(entry.part).to eq(2)
    end
  end

  context "with a subtune past the tune's last" do
    let(:subtune) { 3 }

    it "can't play" do
      expect(entry.error).to eq("no subtune 3: the tune has 2")
    end
  end

  it "ends a subtune on the fallback length once it falls silent" do
    expect([entry.length(1), entry.silence(1)]).to eq([60.0, 5.0])
  end

  context "with --sid and --seconds" do
    let(:arguments) { ["--sid", "6581", "--seconds", "12"] }

    it "takes them over the tune's own" do
      expect([entry.model_name, entry.length(1)]).to eq(["6581", 12.0])
    end

    it "plays the whole length" do
      expect(entry.silence(1)).to be_nil
    end
  end

  context "with a file that isn't a tune" do
    before { File.binwrite(path, "XSID") }

    it "has one subtune and can't play" do
      expect([entry.parts, entry.error]).to eq([1, "Missing PSID or RSID signature"])
    end
  end

  it "reads the tune again once released" do
    tune = entry.tune
    entry.release
    expect(entry.tune).not_to equal(tune)
  end
end
