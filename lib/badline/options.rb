# frozen_string_literal: true

require "optparse"

module Badline
  # The command line of `badline-ruby`. It opens the window for any media,
  # or with --headless or --audio-out plays or renders a .sid tune without
  # one. It loads nothing else from badline, so the executable can parse
  # and reject its arguments before paying for the emulator.
  class Options
    class Error < StandardError; end

    FALLBACK_SECONDS = 60.0

    DEFAULT_RATE = 44_100

    SID_MODELS = { "6581" => :mos6581, "8580" => :mos8580 }.freeze

    BANNER = <<~BANNER.freeze
      Usage: badline-ruby [options] [media]
             badline-ruby --headless [options] tune.sid
             badline-ruby [options] tune.sid --audio-out FILE

      Media can be a .prg/.p00 program, a .d64/.d71/.d81 disk image,
      a .t64 tape archive, a .tap tape, a .crt cartridge, a .sid tune, or
      a directory to mount as device 8. It opens in the emulator window.

      --headless plays a .sid tune on the host's audio device without the
      window, and --audio-out renders it to 16-bit PCM instead. The
      container follows the file's extension, .wav or .aiff. Played on a
      terminal, n or → skips to the next song, p or ← to the previous one,
      space pauses and q quits.

      A .sid file carries no length of its own. Without --seconds the tune is
      looked up by MD5 in HVSC's Songlengths.md5, taken from --songlengths, from
      the DOCUMENTS directory of an HVSC collection above the tune, or from
      $HVSC_BASE. Failing all of those it runs for #{FALLBACK_SECONDS.to_i} seconds.

      Without the window, PSID tunes run on a bare CPU and SID, faster than
      real time. RSID tunes boot the whole machine and run at about half
      real time, so they stutter when played. --filter-chunk 1 runs the
      filter cycle by cycle, which is exact but takes about twice as long.

    BANNER

    attr_reader :media_path, :audio_out, :song, :seconds, :songlengths, :sid_model, :filter_chunk

    alias tune_path media_path

    def self.parse(argv) = new.parse(argv)

    def initialize
      @autostart = true
      @sound = false
      @headless = false
      @jit = true
      @quiet = false
      @tui = true
      @help = false
      @window_only = []
      @headless_only = []
    end

    def parse(argv)
      @media_path, *extra = parser.parse(argv)
      raise Error, "unexpected argument: #{extra.first}" if extra.any?

      validate unless help?
      self
    rescue OptionParser::ParseError => e
      raise Error, e.message
    end

    # Plays or renders a .sid tune without the window.
    def headless? = @headless || render?

    def window? = !headless?

    def render? = !audio_out.nil?

    def rate = @rate || DEFAULT_RATE

    def rate_given? = !@rate.nil?

    def help = parser.help

    def help? = @help

    def autostart? = @autostart

    def sound? = @sound

    def quiet? = @quiet

    def tui? = @tui

    def jit? = @jit

    private

    def validate
      validate_mode
      validate_numbers
      validate_paths
    end

    def validate_mode
      if headless?
        raise Error, "#{@window_only.first} needs the window" if @window_only.any?
        raise Error, "no tune given" unless media_path
        raise Error, "not a .sid tune: #{media_path}" unless File.extname(media_path).casecmp?(".sid")
      elsif @headless_only.any?
        raise Error, "#{@headless_only.first} needs --headless or --audio-out"
      end
    end

    def validate_numbers
      raise Error, "invalid argument: --song #{song}" if song&.< 1
      raise Error, "invalid argument: --seconds #{seconds}" unless seconds.nil? || seconds.positive?
      raise Error, "invalid argument: --rate #{rate}" unless rate.positive?
      raise Error, "invalid argument: --filter-chunk #{filter_chunk}" if filter_chunk&.< 1
    end

    def validate_paths
      [media_path, songlengths].compact.each do |path|
        raise Error, "no such file or directory: #{path}" unless File.exist?(path)
      end
    end

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = BANNER
        opts.separator "Options:"
        define_media_options(opts)
        opts.separator ""
        opts.separator "Window options:"
        define_window_options(opts)
        opts.separator ""
        opts.separator "Options without the window:"
        define_headless_options(opts)
      end
    end

    def define_media_options(opts)
      opts.on("-s", "--song N", Integer, "Subtune of a .sid, from 1 (default: the tune's own)") { |n| @song = n }
      opts.on("--sid MODEL", SID_MODELS,
              "SID to fit: 6581 or 8580 (default: a .sid tune's own, else 6581)") { |model| @sid_model = model }
      opts.on("--disable-jit", "Run without enabling YJIT") { @jit = false }
      opts.on("-h", "--help", "Show this help") { @help = true }
    end

    def define_window_options(opts)
      opts.on("--no-autostart", "Boot to READY. instead of running the program") do
        window_only("--no-autostart") { @autostart = false }
      end
      opts.on("--sound", "Play the SID through the host's audio device (F10 mutes)") do
        window_only("--sound") { @sound = true }
      end
    end

    def define_headless_options(opts)
      opts.on("--headless", "Play a .sid tune in the terminal instead of the window") { @headless = true }
      opts.on("--audio-out FILE", "Render a .sid tune to a .wav or .aiff file") { |path| @audio_out = path }
      define_length_options(opts)
      define_rendering_options(opts)
      opts.on("--quiet", "Don't report progress") { headless_only("--quiet") { @quiet = true } }
      opts.on("--no-tui", "Play without the interactive display, even on a terminal") do
        headless_only("--no-tui") { @tui = false }
      end
    end

    def define_length_options(opts)
      opts.on("--seconds N", Float, "Length to play (default: the tune's own)") do |n|
        headless_only("--seconds") { @seconds = n }
      end
      opts.on("--songlengths PATH", "HVSC Songlengths.md5 to take the length from") do |path|
        headless_only("--songlengths") { @songlengths = path }
      end
    end

    def define_rendering_options(opts)
      opts.on("--rate HZ", Integer, "Sample rate (default: #{DEFAULT_RATE}, or the audio device's own)") do |n|
        headless_only("--rate") { @rate = n }
      end
      opts.on("--filter-chunk N", Integer, "Filter step in cycles, 1 is exact (default: 4)") do |n|
        headless_only("--filter-chunk") { @filter_chunk = n }
      end
    end

    def window_only(flag)
      @window_only << flag
      yield
    end

    def headless_only(flag)
      @headless_only << flag
      yield
    end
  end
end
