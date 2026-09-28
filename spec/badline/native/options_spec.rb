# frozen_string_literal: true

require "spec_helper"
require_relative "../../../native/lib/badline/native/options"

describe Badline::Native::Options do
  def parse(*argv) = described_class.parse(argv)

  let(:existing_file) { File.expand_path("../../../README.md", __dir__) }

  describe "with no arguments" do
    subject(:options) { parse }

    it "boots without media" do
      expect(options.media).to eq("")
    end

    it "autostarts, paced by vsync, with sound, until closed" do
      expect([options.autostart?, options.paced?, options.vsync?, options.sound?, options.frames])
        .to eq([true, true, true, true, 0])
    end

    it "leaves the SID model and the song to the media" do
      expect([options.sid_model, options.song]).to eq([nil, nil])
    end
  end

  it "takes the media" do
    expect(parse(existing_file).media).to eq(existing_file)
  end

  it "takes the media after the options" do
    expect(parse("--sound", existing_file, "--frames", "5").media).to eq(existing_file)
  end

  it "takes an argument after -- as media, even with a dash" do
    expect { parse("--", "-game.prg") }.to raise_error(described_class::Error, "no such file or directory: -game.prg")
  end

  it "picks the 8580" do
    expect(parse("--sid", "8580").sid_model).to eq(:mos8580)
  end

  it "picks the 6581 with --sid=6581" do
    expect(parse("--sid=6581").sid_model).to eq(:mos6581)
  end

  it "takes a song" do
    expect(parse("--song", "3").song).to eq(3)
  end

  it "takes a song with -s" do
    expect(parse("-s", "2").song).to eq(2)
  end

  it "boots to READY. with --no-autostart" do
    expect(parse("--no-autostart").autostart?).to be(false)
  end

  it "mounts disks read-write unless --read-only asks otherwise" do
    expect([parse.read_only?, parse("--read-only").read_only?]).to eq([false, true])
  end

  it "turns sound off with --no-sound" do
    expect(parse("--no-sound").sound?).to be(false)
  end

  it "takes whichever of --sound and --no-sound comes last" do
    expect(parse("--no-sound", "--sound").sound?).to be(true)
  end

  it "marks --sound as the default in the help" do
    expect(described_class::HELP).to include("(F10 mutes) (default)")
  end

  it "turns vsync off with --no-vsync" do
    expect(parse("--no-vsync").vsync?).to be(false)
  end

  it "takes the testing knobs" do
    options = parse("--frames=150", "--unpaced", "--screenshot", "ready.bmp")
    expect([options.frames, options.paced?, options.screenshot]).to eq([150, false, "ready.bmp"])
  end

  it "asks for help with -h" do
    expect(parse("-h").help?).to be(true)
  end

  it "asks for the version" do
    expect(parse("--version").version?).to be(true)
  end

  it "skips the checks when asked for help" do
    expect(parse("--help", "missing.prg").help?).to be(true)
  end

  it "lists every option in the help" do
    %w[--song --sid --no-autostart --sound --no-sound --no-vsync --help --version
       --frames --unpaced --screenshot].each do |flag|
      expect(described_class::HELP).to include(flag)
    end
  end

  {
    %w[--turbo] => "invalid option: --turbo",
    %w[--sid 6582] => "invalid argument: --sid 6582",
    %w[--song two] => "invalid argument: --song two",
    %w[--song 0] => "invalid argument: --song 0",
    %w[--frames -1] => "invalid argument: --frames -1",
    %w[--song] => "missing argument: --song",
    %w[--sound=yes] => "needless argument: --sound=yes",
    %w[missing.prg] => "no such file or directory: missing.prg",
    %w[a.prg b.prg] => "unexpected argument: b.prg"
  }.each do |argv, message|
    it "refuses #{argv.join(' ')}" do
      expect { parse(*argv) }.to raise_error(described_class::Error, message)
    end
  end
end
