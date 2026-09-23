# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../../support/tiny_sid"

describe Badline::Audio::CLI do
  subject(:cli) { described_class.new(options, out:) }

  let(:dir) { Dir.mktmpdir }
  let(:out) { StringIO.new }
  let(:output) { File.join(dir, "out.wav") }
  let(:arguments) { ["--seconds", "0.05", "--rate", "8000"] }
  let(:options) { Badline::Audio::Options.parse(arguments + [tune_path, "-o", output]) }

  before { File.binwrite(tune_path, TinySID.bytes) }
  after { FileUtils.remove_entry(dir) }

  def tune_path = File.join(dir, "tune.sid")
  def tune = Badline::Storage::SIDFile.new(tune_path)

  def songlengths(line)
    File.join(dir, "Songlengths.md5").tap { |path| File.write(path, "[Database]\n#{line}\n") }
  end

  describe "#song" do
    it "defaults to the tune's start song" do
      expect(cli.song).to eq(1)
    end

    context "with a song selected" do
      let(:arguments) { ["-s", "2"] }

      it "takes it" do
        expect(cli.song).to eq(2)
      end
    end

    context "with a song past the tune's last" do
      let(:arguments) { ["-s", "3"] }

      it "raises" do
        expect { cli.song }.to raise_error(described_class::Error, /no song 3: the tune has 2/)
      end
    end
  end

  describe "#seconds" do
    let(:arguments) { ["-s", "2", "--songlengths", songlengths("#{tune.md5}=0:10 1:02.5")] }

    it "looks the song up in the database" do
      expect(cli.seconds).to eq(62.5)
    end

    context "with --seconds" do
      let(:arguments) { ["--seconds", "3", "--songlengths", songlengths("#{tune.md5}=0:10")] }

      it "takes that over the database" do
        expect(cli.seconds).to eq(3.0)
      end
    end

    context "with a tune the database doesn't list" do
      let(:arguments) { ["--songlengths", songlengths("0123=0:10")] }

      it "falls back to a minute" do
        expect(cli.seconds).to eq(60.0)
      end
    end
  end

  describe "#sid_model" do
    it "follows the tune" do
      expect(cli.sid_model).to eq(:mos6581)
    end

    context "with --sid" do
      let(:arguments) { ["--sid", "8580"] }

      it "takes the override" do
        expect(cli.sid_model).to eq(:mos8580)
      end
    end
  end

  describe "#tune" do
    before { File.binwrite(tune_path, "XSID") }

    it "reports a file that isn't a tune" do
      expect { cli.tune }.to raise_error(described_class::Error, /tune\.sid/)
    end
  end

  describe "#run" do
    let(:arguments) { ["--seconds", "0.05", "--rate", "8000", "-s", "2", "--filter-chunk", "1"] }

    def reference = File.join(dir, "reference.wav")

    before do
      renderer = Badline::Audio::Renderer.new(tune, seconds: 0.05, song: 2, rate: 8000)
      renderer.filter_chunk = 1
      renderer.render(reference)
    end

    it "renders the same file as the renderer does" do
      cli.run
      expect(File.binread(output)).to eq(File.binread(reference))
    end

    it "says what it renders" do
      cli.run
      expect(out.string).to include("TUNE / AUTHOR / 1987 (song 2)", "Rendering 0.05s for the 6581")
    end

    it "reports the speed" do
      cli.run
      expect(out.string).to match(/Wrote .*out\.wav in .*x real time/)
    end

    context "with an output it can't write" do
      let(:output) { File.join(dir, "out.ogg") }

      it "raises" do
        expect { cli.run }.to raise_error(described_class::Error, /\.ogg/)
      end
    end

    context "when quiet" do
      let(:arguments) { ["--seconds", "0.05", "--quiet"] }

      it "leaves out the progress" do
        cli.run
        expect(out.string).not_to include("\r")
      end
    end
  end
end
