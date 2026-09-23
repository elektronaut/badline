# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Audio::Options do
  subject(:options) { described_class.parse(argv) }

  let(:dir) { Dir.mktmpdir }
  let(:tune_path) { File.join(dir, "tune.sid") }
  let(:argv) { [tune_path] }

  before { File.binwrite(tune_path, "PSID") }
  after { FileUtils.remove_entry(dir) }

  describe "defaults" do
    it "takes the tune from the first argument" do
      expect(options.tune_path).to eq(tune_path)
    end

    it "leaves the song to the tune" do
      expect(options.song).to be_nil
    end

    it "leaves the length to the tune" do
      expect(options.seconds).to be_nil
    end

    it "plays rather than renders" do
      expect(options.render?).to be(false)
    end

    it "asks for 44.1 kHz" do
      expect(options.rate).to eq(44_100)
    end

    it "lets the audio device pick its own rate" do
      expect(options.rate_given?).to be(false)
    end

    it "leaves the SID model to the tune" do
      expect(options.sid_model).to be_nil
    end

    it "leaves the filter chunk to the SID" do
      expect(options.filter_chunk).to be_nil
    end

    it "enables YJIT" do
      expect(options.jit?).to be(true)
    end

    it "shows the interactive display on a terminal" do
      expect(options.tui?).to be(true)
    end

    it "reports progress" do
      expect(options.quiet?).to be(false)
    end
  end

  describe "the song" do
    %w[--song -s].each do |flag|
      context "with #{flag}" do
        let(:argv) { [flag, "3", tune_path] }

        it "selects the subtune" do
          expect(options.song).to eq(3)
        end
      end
    end

    context "with song 0" do
      let(:argv) { ["--song", "0", tune_path] }

      it "is rejected, songs counting from 1" do
        expect { options }.to raise_error(described_class::Error, /--song 0/)
      end
    end

    context "with a song that isn't a number" do
      let(:argv) { ["--song", "two", tune_path] }

      it "is rejected" do
        expect { options }.to raise_error(described_class::Error, /two/)
      end
    end
  end

  describe "the output" do
    %w[--output -o].each do |flag|
      context "with #{flag}" do
        let(:argv) { [tune_path, flag, "out.aiff"] }

        it "renders to that file" do
          expect([options.render?, options.output]).to eq([true, "out.aiff"])
        end
      end
    end

    context "with a second argument" do
      let(:argv) { [tune_path, "out.aiff"] }

      it "renders to that file" do
        expect(options.output).to eq("out.aiff")
      end
    end

    context "with both" do
      let(:argv) { [tune_path, "positional.wav", "-o", "flag.wav"] }

      it "takes the option" do
        expect(options.output).to eq("flag.wav")
      end
    end

    context "with a third argument" do
      let(:argv) { [tune_path, "out.wav", "more.wav"] }

      it "is rejected" do
        expect { options }.to raise_error(described_class::Error, /more\.wav/)
      end
    end
  end

  describe "the rendering options" do
    let(:argv) do
      ["--seconds", "12.5", "--rate", "48000", "--sid", "8580", "--filter-chunk", "1",
       "--quiet", "--disable-jit", "--no-tui", tune_path]
    end

    it "parses each of them" do
      expect([options.seconds, options.rate, options.sid_model, options.filter_chunk,
              options.quiet?, options.jit?, options.tui?])
        .to eq([12.5, 48_000, :mos8580, 1, true, false, false])
    end

    it "holds the device to the rate asked for" do
      expect(options.rate_given?).to be(true)
    end
  end

  describe "validation" do
    {
      "no tune" => [[], /no tune/],
      "a missing tune" => [["missing.sid"], /no such file: missing\.sid/],
      "a missing song length database" => [%w[--songlengths missing.md5], /missing\.md5/],
      "an unknown SID" => [%w[--sid 6582], /6582/],
      "a zero filter chunk" => [%w[--filter-chunk 0], /--filter-chunk 0/],
      "a zero rate" => [%w[--rate 0], /--rate 0/],
      "a negative length" => [%w[--seconds -1], /--seconds -1/],
      "an unknown option" => [%w[--loud], /--loud/]
    }.each do |name, (args, message)|
      context "with #{name}" do
        let(:argv) { args + (args.empty? || args.first.end_with?(".sid") ? [] : [tune_path]) }

        it "raises" do
          expect { options }.to raise_error(described_class::Error, message)
        end
      end
    end
  end

  describe "--help" do
    let(:argv) { ["--help"] }

    it "asks for help without needing a tune" do
      expect(options.help?).to be(true)
    end

    it "describes the options" do
      expect(options.help).to include("Usage: badline-sid", "--song", "--output")
    end
  end
end
