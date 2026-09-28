# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Options do
  subject(:options) { described_class.parse(argv) }

  let(:dir) { Dir.mktmpdir }
  let(:tune_path) { File.join(dir, "tune.sid") }
  let(:program_path) { File.join(dir, "game.prg") }
  let(:argv) { [tune_path] }

  before do
    File.binwrite(tune_path, "PSID")
    File.binwrite(program_path, "\x01\x08")
  end

  after { FileUtils.remove_entry(dir) }

  describe "defaults" do
    it "takes the media from the first argument" do
      expect([options.media_path, options.tune_path]).to eq([tune_path, tune_path])
    end

    it "opens the window" do
      expect([options.window?, options.headless?, options.render?]).to eq([true, false, false])
    end

    it "autostarts the media" do
      expect(options.autostart?).to be(true)
    end

    it "keeps the window quiet" do
      expect(options.sound?).to be(false)
    end

    it "keeps the setup and timing to itself" do
      expect(options.verbose?).to be(false)
    end

    it "mounts disk images read-write" do
      expect(options.read_only?).to be(false)
    end

    it "leaves the song to the tune" do
      expect(options.song).to be_nil
    end

    it "leaves the length to the tune" do
      expect(options.seconds).to be_nil
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

  describe "the window" do
    context "without media" do
      let(:argv) { [] }

      it "boots to READY." do
        expect([options.window?, options.media_path]).to eq([true, nil])
      end
    end

    context "with a program" do
      let(:argv) { [program_path] }

      it "takes it" do
        expect(options.media_path).to eq(program_path)
      end
    end

    context "with --no-autostart and --sound" do
      let(:argv) { ["--no-autostart", "--sound", program_path] }

      it "parses each of them" do
        expect([options.autostart?, options.sound?]).to eq([false, true])
      end
    end

    context "with --read-only" do
      let(:argv) { ["--read-only", program_path] }

      it "mounts disk images write-protected" do
        expect(options.read_only?).to be(true)
      end
    end

    context "with --verbose" do
      let(:argv) { ["--verbose", program_path] }

      it "prints the setup and timing" do
        expect(options.verbose?).to be(true)
      end
    end

    context "with the SID to fit" do
      let(:argv) { ["--sid", "8580", program_path] }

      it "takes it" do
        expect(options.sid_model).to eq(:mos8580)
      end
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

  describe "--headless" do
    let(:argv) { ["--headless", tune_path] }

    it "plays without the window" do
      expect([options.headless?, options.window?, options.render?]).to eq([true, false, false])
    end
  end

  describe "the output" do
    context "with --audio-out" do
      let(:argv) { [tune_path, "--audio-out", "out.aiff"] }

      it "renders to that file without the window" do
        expect([options.render?, options.headless?, options.audio_out]).to eq([true, true, "out.aiff"])
      end
    end

    context "with -o" do
      let(:argv) { [tune_path, "-o", "out.aiff"] }

      it "is rejected, leaving -o free" do
        expect { options }.to raise_error(described_class::Error, /-o/)
      end
    end

    context "with a second argument" do
      let(:argv) { [tune_path, "out.aiff"] }

      it "is rejected" do
        expect { options }.to raise_error(described_class::Error, /unexpected argument: out\.aiff/)
      end
    end
  end

  describe "the options without the window" do
    let(:argv) do
      ["--headless", "--seconds", "12.5", "--rate", "48000", "--sid", "8580", "--filter-chunk", "1",
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
      "a missing media file" => [["missing.prg"], /no such file or directory: missing\.prg/],
      "a missing tune" => [%w[--headless missing.sid], /no such file or directory: missing\.sid/],
      "no tune without the window" => [%w[--headless], /no tune/],
      "an unknown SID" => [%w[--sid 6582], /6582/],
      "an unknown option" => [%w[--loud], /--loud/]
    }.each do |name, (args, message)|
      context "with #{name}" do
        let(:argv) { args }

        it "raises" do
          expect { options }.to raise_error(described_class::Error, message)
        end
      end
    end

    {
      "a missing song length database" => [%w[--songlengths missing.md5], /missing\.md5/],
      "a zero filter chunk" => [%w[--filter-chunk 0], /--filter-chunk 0/],
      "a zero rate" => [%w[--rate 0], /--rate 0/],
      "a negative length" => [%w[--seconds -1], /--seconds -1/]
    }.each do |name, (args, message)|
      context "with #{name}" do
        let(:argv) { ["--headless", *args, tune_path] }

        it "raises" do
          expect { options }.to raise_error(described_class::Error, message)
        end
      end
    end

    context "with a program without the window" do
      let(:argv) { ["--headless", program_path] }

      it "raises" do
        expect { options }.to raise_error(described_class::Error, /not a \.sid tune: .*game\.prg/)
      end
    end

    %w[--seconds=10 --songlengths=x --rate=8000 --filter-chunk=1 --quiet --no-tui].each do |arg|
      context "with #{arg} in the window" do
        let(:argv) { [arg, tune_path] }

        it "raises" do
          expect { options }.to raise_error(described_class::Error,
                                            /#{arg.split('=').first} needs --headless or --audio-out/)
        end
      end
    end

    %w[--no-autostart --sound --read-only --verbose].each do |arg|
      context "with #{arg} without the window" do
        let(:argv) { ["--headless", arg, tune_path] }

        it "raises" do
          expect { options }.to raise_error(described_class::Error, /#{arg} needs the window/)
        end
      end
    end
  end

  describe "--help" do
    let(:argv) { ["--help"] }

    it "asks for help without needing media" do
      expect(options.help?).to be(true)
    end

    it "describes the options" do
      expect(options.help).to include("Usage: badline-ruby", "--headless", "--song", "--audio-out", "--sound",
                                      "--verbose")
    end
  end
end
