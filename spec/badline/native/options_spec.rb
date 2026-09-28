# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/options"
require_relative "../../../native/lib/badline/native/options"
require_relative "../../../native/lib/badline/native/help"

describe Badline::Native::Options do
  def parse(*argv) = described_class.parse(argv)

  let(:existing_file) { File.expand_path("../../../README.md", __dir__) }
  # The options only check that a tune exists.
  let(:dir) { Dir.mktmpdir }
  let(:tune) { File.join(dir, "tune.sid").tap { |path| File.write(path, "") } }

  after { FileUtils.remove_entry(dir) }

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
       --frames --unpaced --screenshot --headless --audio-out --seconds --songlengths
       --rate --filter-chunk --quiet --no-tui].each do |flag|
      expect(described_class::HELP).to include(flag)
    end
  end

  it "opens the window without --headless or --audio-out" do
    expect([parse.window?, parse.headless?, parse.render?]).to eq([true, false, false])
  end

  it "plays without the window with --headless" do
    options = parse("--headless", tune)
    expect([options.headless?, options.window?, options.render?, options.tune_path])
      .to eq([true, false, false, tune])
  end

  it "renders without the window with --audio-out" do
    options = parse(tune, "--audio-out", "out.aiff")
    expect([options.render?, options.headless?, options.audio_out]).to eq([true, true, "out.aiff"])
  end

  describe "without the window" do
    subject(:options) do
      parse("--headless", "--seconds", "12.5", "--rate", "48000", "--sid", "8580", "--filter-chunk=1",
            "--quiet", "--no-tui", tune)
    end

    it "parses each of the options" do
      expect([options.seconds, options.rate, options.sid_model, options.filter_chunk, options.quiet?, options.tui?])
        .to eq([12.5, 48_000, :mos8580, 1, true, false])
    end

    it "holds the device to the rate asked for" do
      expect(options.rate_given?).to be(true)
    end

    it "defaults as badline-ruby does" do
      defaults = parse("--headless", tune)
      expect([defaults.seconds, defaults.songlengths, defaults.rate, defaults.rate_given?, defaults.filter_chunk,
              defaults.quiet?, defaults.tui?, defaults.fallback_seconds])
        .to eq([nil, nil, 44_100, false, nil, false, true, 60.0])
    end

    it "takes the song length database" do
      expect(parse("--headless", "--songlengths", existing_file, tune).songlengths).to eq(existing_file)
    end

    %w[1.5 .5 2e1 +3].each do |value|
      it "takes #{value} seconds as OptionParser's Float does" do
        expect(parse("--headless", "--seconds", value, tune).seconds).to eq(Float(value))
      end
    end
  end

  describe "the checks badline-ruby makes" do
    it "describes its options as its help does" do
      lines = Badline::Options.new.help.lines.grep(/\A\s+-/).grep_v(/--disable-jit/)
      expect(lines.reject { |line| described_class::HELP.include?(line.chomp) }).to be_empty
    end

    {
      %w[--headless] => "no tune given",
      %w[--audio-out out.wav] => "no tune given",
      %w[--headless missing.sid] => "no such file or directory: missing.sid"
    }.each do |argv, message|
      it "refuses #{argv.join(' ')}" do
        expect { parse(*argv) }.to raise_error(described_class::Error, message)
      end
    end

    {
      %w[--headless --seconds 0] => "invalid argument: --seconds 0.0",
      %w[--headless --seconds -1] => "invalid argument: --seconds -1.0",
      %w[--headless --seconds abc] => "invalid argument: --seconds abc",
      %w[--headless --rate 0] => "invalid argument: --rate 0",
      %w[--headless --filter-chunk 0] => "invalid argument: --filter-chunk 0",
      %w[--headless --songlengths missing.md5] => "no such file or directory: missing.md5",
      %w[--headless --sound] => "--sound needs the window",
      %w[--headless --no-autostart] => "--no-autostart needs the window",
      %w[--headless --read-only] => "--read-only needs the window",
      %w[--headless --no-sound] => "--no-sound needs the window",
      %w[--headless --frames 3] => "--frames needs the window",
      %w[--seconds=10] => "--seconds needs --headless or --audio-out",
      %w[--songlengths x] => "--songlengths needs --headless or --audio-out",
      %w[--rate 8000] => "--rate needs --headless or --audio-out",
      %w[--filter-chunk 1] => "--filter-chunk needs --headless or --audio-out",
      %w[--quiet] => "--quiet needs --headless or --audio-out",
      %w[--no-tui] => "--no-tui needs --headless or --audio-out"
    }.each do |argv, message|
      it "refuses #{argv.join(' ')} with a tune" do
        expect { parse(*argv, tune) }.to raise_error(described_class::Error, message)
      end
    end

    it "refuses a program without the window" do
      expect { parse("--headless", existing_file) }
        .to raise_error(described_class::Error, "not a .sid tune: #{existing_file}")
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
