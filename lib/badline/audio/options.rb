# frozen_string_literal: true

require "optparse"

module Badline
  module Audio
    # The command line of `badline-sid`. It loads nothing else from badline,
    # so the executable can parse and reject its arguments before paying for
    # the emulator.
    class Options
      class Error < StandardError; end

      FALLBACK_SECONDS = 60.0

      DEFAULT_RATE = 44_100

      SID_MODELS = { "6581" => :mos6581, "8580" => :mos8580 }.freeze

      BANNER = <<~BANNER.freeze
        Usage: badline-sid [options] tune.sid [-o output]

        Plays a .sid tune on the host's audio device, or with an output file
        renders it to 16-bit PCM instead. The container follows the output
        file's extension, .wav or .aiff.

        A .sid file carries no length of its own. Without --seconds the tune is
        looked up by MD5 in HVSC's Songlengths.md5, taken from --songlengths, from
        the DOCUMENTS directory of an HVSC collection above the tune, or from
        $HVSC_BASE. Failing all of those it runs for #{FALLBACK_SECONDS.to_i} seconds.

        PSID tunes run on a bare CPU and SID, faster than real time. RSID
        tunes boot the whole machine and run at about half real time, so
        they stutter when played. --filter-chunk 1 runs the filter cycle by
        cycle, which is exact but takes about twice as long.

        Options:
      BANNER

      attr_reader :tune_path, :output, :song, :seconds, :songlengths, :sid_model, :filter_chunk

      def self.parse(argv) = new.parse(argv)

      def initialize
        @jit = true
        @quiet = false
        @help = false
      end

      def parse(argv)
        arguments = parser.parse(argv)
        @tune_path, positional_output, *extra = arguments
        raise Error, "unexpected argument: #{extra.first}" if extra.any?

        @output ||= positional_output
        validate unless help?
        self
      rescue OptionParser::ParseError => e
        raise Error, e.message
      end

      def render? = !output.nil?

      def rate = @rate || DEFAULT_RATE

      def rate_given? = !@rate.nil?

      def help = parser.help

      def help? = @help

      def quiet? = @quiet

      def jit? = @jit

      private

      def validate
        raise Error, "no tune given" unless tune_path

        validate_numbers
        validate_paths
      end

      def validate_numbers
        raise Error, "invalid argument: --song #{song}" if song&.< 1
        raise Error, "invalid argument: --seconds #{seconds}" unless seconds.nil? || seconds.positive?
        raise Error, "invalid argument: --rate #{rate}" unless rate.positive?
        raise Error, "invalid argument: --filter-chunk #{filter_chunk}" if filter_chunk&.< 1
      end

      def validate_paths
        [tune_path, songlengths].compact.each do |path|
          raise Error, "no such file: #{path}" unless File.exist?(path)
        end
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = BANNER
          define_tune_options(opts)
          define_output_options(opts)
          define_run_options(opts)
        end
      end

      def define_tune_options(opts)
        opts.on("-s", "--song N", Integer, "Subtune to play, from 1 (default: the tune's own)") { |n| @song = n }
        opts.on("--seconds N", Float, "Length to play (default: the tune's own)") { |n| @seconds = n }
        opts.on("--songlengths PATH", "HVSC Songlengths.md5 to take the length from") { |path| @songlengths = path }
        opts.on("--sid MODEL", SID_MODELS,
                "SID to play on: 6581 or 8580 (default: the tune's own, else 6581)") { |model| @sid_model = model }
      end

      def define_output_options(opts)
        opts.on("-o", "--output PATH", "Render to a .wav or .aiff file instead of playing") { |path| @output = path }
        opts.on("--rate HZ", Integer,
                "Sample rate (default: #{DEFAULT_RATE}, or the audio device's own)") { |n| @rate = n }
        opts.on("--filter-chunk N", Integer, "Filter step in cycles, 1 is exact (default: 4)") do |n|
          @filter_chunk = n
        end
      end

      def define_run_options(opts)
        opts.on("--quiet", "Don't report progress") { @quiet = true }
        opts.on("--disable-jit", "Run without enabling YJIT") { @jit = false }
        opts.on("-h", "--help", "Show this help") { @help = true }
      end
    end
  end
end
