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

    context "with --true-drive" do
      let(:argv) { ["--true-drive", program_path] }

      it "puts a true drive on device 8" do
        expect(options.true_drive?).to be(true)
      end
    end

    context "without --true-drive" do
      let(:argv) { [program_path] }

      it "leaves device 8 to the KERNAL traps" do
        expect(options.true_drive?).to be(false)
      end
    end

    context "with --ntsc" do
      let(:argv) { ["--ntsc", program_path] }

      it "runs an NTSC machine" do
        expect(options.ntsc?).to be(true)
      end
    end

    context "without --ntsc" do
      let(:argv) { [program_path] }

      it "runs a PAL machine" do
        expect(options.ntsc?).to be(false)
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

    context "with an REU" do
      let(:argv) { ["--reu", "512", program_path] }

      it "takes its size in K" do
        expect(options.reu).to eq(512)
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
       "--quiet", "--disable-jit", "--no-tui", "--all-songs", tune_path]
    end

    it "parses each of them" do
      expect([options.seconds, options.rate, options.sid_model, options.filter_chunk,
              options.quiet?, options.jit?, options.tui?, options.all_songs?])
        .to eq([12.5, 48_000, :mos8580, 1, true, false, false, true])
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
      "an unknown REU size" => [%w[--reu 100], /100/],
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

    %w[--seconds=10 --songlengths=x --rate=8000 --filter-chunk=1 --quiet --no-tui --all-songs].each do |arg|
      context "with #{arg} in the window" do
        let(:argv) { [arg, tune_path] }

        it "raises" do
          expect { options }.to raise_error(described_class::Error,
                                            /#{arg.split('=').first} needs --headless or --audio-out/)
        end
      end
    end

    %w[--no-autostart --sound --read-only --verbose --true-drive --reu=512].each do |arg|
      context "with #{arg} without the window" do
        let(:argv) { ["--headless", arg, tune_path] }

        it "raises" do
          expect { options }.to raise_error(described_class::Error, /#{arg.split('=').first} needs the window/)
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
                                      "--verbose", "--true-drive")
    end

    it "lays each option out as OptionParser did" do
      expect(options.help.lines).to include(
        "    -s, --song N                     Subtune of a .sid, from 1 (default: the tune's own)\n",
        "        --sound                      Play the SID through the host's audio device (F10 mutes)\n"
      )
    end
  end

  describe "the options the native build alone takes" do
    %w[--version --no-sound].each do |arg|
      context "with #{arg}" do
        let(:argv) { [arg] }

        it "is rejected" do
          expect { options }.to raise_error(described_class::Error, "invalid option: #{arg}")
        end
      end
    end
  end

  describe "the window's pacing and testing options" do
    let(:argv) { %w[--no-vsync --frames=150 --unpaced --screenshot ready.bmp --save-snapshot ready.vsf] }

    it "are taken" do
      expect([options.vsync?, options.frames, options.paced?, options.screenshot, options.save_snapshot])
        .to eq([false, 150, false, "ready.bmp", "ready.vsf"])
    end
  end

  describe "the timeline" do
    let(:script_path) { File.join(dir, "events.txt") }

    def events = options.timeline.map { |event| [event.frame, event.action, event.argument] }

    context "with --at" do
      let(:argv) { ["--at", "3500:key=space", "--at=250,500:screenshot=shot%d.bmp", "--at", "9:quit"] }

      it "takes an event at each of its frames" do
        expect(events).to eq([[3500, "key", "space"], [250, "screenshot", "shot%d.bmp"],
                              [500, "screenshot", "shot%d.bmp"], [9, "quit", ""]])
      end
    end

    context "with --script" do
      let(:argv) { ["--script", script_path] }

      it "takes an event a line, skipping blank lines and comments" do
        File.write(script_path, "# boot\n\n150:type=print 6*7\\n\n  200:screenshot=ready.bmp  \n")
        expect(events).to eq([[150, "type", "print 6*7\\n"], [200, "screenshot", "ready.bmp"]])
      end

      it "names the line it can't take" do
        File.write(script_path, "150:typo\n")
        expect { options }.to raise_error(described_class::Error, "invalid argument: --script #{script_path}: 150:typo")
      end
    end

    context "with media to insert" do
      let(:argv) { ["--at", "10:insert=#{dir}", "--at", "20:eject=tape"] }

      it "takes a directory and what comes out" do
        expect(events).to eq([[10, "insert", dir], [20, "eject", "tape"]])
      end
    end

    {
      "frame 0" => "0:quit", "no frame" => "quit", "a frame that isn't a number" => "x:quit",
      "an unknown event" => "1:jump", "an argument to quit" => "1:quit=now", "a key without a name" => "1:key",
      "something that won't eject" => "1:eject=floppy", "a missing disk" => "1:insert=missing.d64",
      "a program to insert" => "1:insert=PROGRAM"
    }.each do |name, event|
      context "with #{name}" do
        let(:argv) { ["--at", event.sub("PROGRAM", program_path)] }

        it "raises" do
          expect { options }.to raise_error(described_class::Error, /invalid argument: --at/)
        end
      end
    end

    context "with a missing script" do
      let(:argv) { %w[--script missing.txt] }

      it "raises" do
        expect { options }.to raise_error(described_class::Error, "no such file: missing.txt")
      end
    end

    context "without the window" do
      let(:argv) { ["--headless", "--at", "1:quit", tune_path] }

      it "raises" do
        expect { options }.to raise_error(described_class::Error, "--at needs the window")
      end
    end
  end

  describe "each build's help" do
    [false, true].each do |native|
      it "lists what #{native ? 'badline' : 'badline-ruby'} takes, and no more" do
        flags = described_class.new(native:).help.scan(/^ +(?:-\w, )?(--[\w-]+)/).flatten
        expect(flags).to eq(described_class::TABLE.map(&:name).reject { |flag| rejected?(flag, native) })
      end
    end

    def rejected?(flag, native)
      described_class.parse(["--help", flag], native:)
      false
    rescue described_class::Error => e
      e.message.start_with?("invalid option")
    end
  end

  describe "in the native build" do
    def parse(*argv) = described_class.parse(argv, native: true)

    let(:help) { described_class.new(native: true).help }

    describe "with no arguments" do
      subject(:options) { parse }

      it "boots without media" do
        expect(options.media_path).to be_nil
      end

      it "keeps the setup and timing to itself" do
        expect(options.verbose?).to be(false)
      end

      it "autostarts, paced by vsync, with sound, until closed" do
        expect([options.autostart?, options.paced?, options.vsync?, options.sound?, options.frames])
          .to eq([true, true, true, true, 0])
      end

      it "leaves device 8 to the KERNAL traps" do
        expect(options.true_drive?).to be(false)
      end

      it "leaves the SID model and the song to the media" do
        expect([options.sid_model, options.song]).to eq([nil, nil])
      end

      it "plugs in no REU" do
        expect(options.reu).to be_nil
      end
    end

    it "takes the media" do
      expect(parse(program_path).media_path).to eq(program_path)
    end

    it "takes the media after the options" do
      expect(parse("--sound", program_path, "--frames", "5").media_path).to eq(program_path)
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

    it "plugs in an REU of the size asked for" do
      expect(parse("--reu", "512").reu).to eq(512)
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

    it "runs an NTSC machine with --ntsc" do
      expect(parse("--ntsc").ntsc?).to be(true)
    end

    it "puts a true drive on device 8 with --true-drive" do
      expect(parse("--true-drive").true_drive?).to be(true)
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
      expect(help).to include("(F10 mutes) (default)")
    end

    it "turns vsync off with --no-vsync" do
      expect(parse("--no-vsync").vsync?).to be(false)
    end

    it "prints the setup and timing with --verbose" do
      expect(parse("--verbose").verbose?).to be(true)
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

    it "takes a file to save a snapshot to after the last frame" do
      expect(parse("--frames", "10", "--save-snapshot", "ready.vsf").save_snapshot).to eq("ready.vsf")
    end

    it "knows a .vsf snapshot among the media" do
      path = File.join(dir, "saved.VSF").tap { |file| File.write(file, "") }
      expect(parse(path).snapshot?).to be(true)
    end

    it "skips the checks when asked for help" do
      expect(parse("--help", "missing.prg").help?).to be(true)
    end

    it "lists every option in the help" do
      %w[--song --sid --no-autostart --true-drive --reu --ntsc --sound --no-sound --no-vsync --verbose --help --version
         --frames --unpaced --screenshot --save-snapshot --headless --audio-out --seconds --songlengths
         --rate --filter-chunk --quiet --no-tui --all-songs].each do |flag|
        expect(help).to include(flag)
      end
    end

    it "opens the window without --headless or --audio-out" do
      expect([parse.window?, parse.headless?, parse.render?]).to eq([true, false, false])
    end

    it "plays without the window with --headless" do
      options = parse("--headless", tune_path)
      expect([options.headless?, options.window?, options.render?, options.tune_path])
        .to eq([true, false, false, tune_path])
    end

    it "renders without the window with --audio-out" do
      options = parse(tune_path, "--audio-out", "out.aiff")
      expect([options.render?, options.headless?, options.audio_out]).to eq([true, true, "out.aiff"])
    end

    describe "without the window" do
      subject(:options) do
        parse("--headless", "--seconds", "12.5", "--rate", "48000", "--sid", "8580", "--filter-chunk=1",
              "--quiet", "--no-tui", "--all-songs", tune_path)
      end

      it "parses each of the options" do
        expect([options.seconds, options.rate, options.sid_model, options.filter_chunk, options.quiet?, options.tui?,
                options.all_songs?])
          .to eq([12.5, 48_000, :mos8580, 1, true, false, true])
      end

      it "holds the device to the rate asked for" do
        expect(options.rate_given?).to be(true)
      end

      it "defaults as badline-ruby does" do
        defaults = parse("--headless", tune_path)
        expect([defaults.seconds, defaults.songlengths, defaults.rate, defaults.rate_given?, defaults.filter_chunk,
                defaults.quiet?, defaults.tui?, defaults.all_songs?, defaults.fallback_seconds,
                defaults.silence_seconds])
          .to eq([nil, nil, 44_100, false, nil, false, true, false, 60.0, 5.0])
      end

      it "takes the song length database" do
        expect(parse("--headless", "--songlengths", program_path, tune_path).songlengths).to eq(program_path)
      end

      %w[1.5 .5 2e1 +3].each do |value|
        it "takes #{value} seconds as OptionParser's Float does" do
          expect(parse("--headless", "--seconds", value, tune_path).seconds).to eq(Float(value))
        end
      end
    end

    describe "the checks badline-ruby makes" do
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
        %w[--headless --reu 512] => "--reu needs the window",
        %w[--headless --no-sound] => "--no-sound needs the window",
        %w[--headless --verbose] => "--verbose needs the window",
        %w[--headless --true-drive] => "--true-drive needs the window",
        %w[--headless --frames 3] => "--frames needs the window",
        %w[--seconds=10] => "--seconds needs --headless or --audio-out",
        %w[--songlengths x] => "--songlengths needs --headless or --audio-out",
        %w[--rate 8000] => "--rate needs --headless or --audio-out",
        %w[--filter-chunk 1] => "--filter-chunk needs --headless or --audio-out",
        %w[--quiet] => "--quiet needs --headless or --audio-out",
        %w[--no-tui] => "--no-tui needs --headless or --audio-out",
        %w[--all-songs] => "--all-songs needs --headless or --audio-out"
      }.each do |argv, message|
        it "refuses #{argv.join(' ')} with a tune_path" do
          expect { parse(*argv, tune_path) }.to raise_error(described_class::Error, message)
        end
      end

      it "refuses a program without the window" do
        expect { parse("--headless", program_path) }
          .to raise_error(described_class::Error, "not a .sid tune: #{program_path}")
      end
    end

    {
      %w[--turbo] => "invalid option: --turbo",
      %w[--disable-jit] => "invalid option: --disable-jit",
      %w[--sid 6582] => "invalid argument: --sid 6582",
      %w[--reu 100] => "invalid argument: --reu 100",
      %w[--song two] => "invalid argument: --song two",
      %w[--song 0] => "invalid argument: --song 0",
      %w[--frames -1] => "invalid argument: --frames -1",
      %w[--song] => "missing argument: --song",
      %w[--sound=yes] => "needless argument: --sound=yes",
      %w[--true-drive=yes] => "needless argument: --true-drive=yes",
      %w[missing.prg] => "no such file or directory: missing.prg",
      %w[a.prg b.prg] => "unexpected argument: b.prg"
    }.each do |argv, message|
      it "refuses #{argv.join(' ')}" do
        expect { parse(*argv) }.to raise_error(described_class::Error, message)
      end
    end
  end
end
