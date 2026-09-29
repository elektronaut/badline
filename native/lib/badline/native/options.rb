# frozen_string_literal: true

module Badline
  module Native
    # The command line of the native badline: badline-ruby's options, window
    # and headless (--headless, --audio-out and the rest), plus --no-sound,
    # --no-vsync, --version and the testing knobs --frames, --unpaced,
    # --screenshot and --save-snapshot. Spinel has no OptionParser, so it parses by hand. Values
    # come as `--song 2` or `--song=2`, and `--` ends the options.
    class Options
      class Error < StandardError; end

      # Whether the SID plays in the window unless --sound or --no-sound
      # says otherwise.
      SOUND = true

      FALLBACK_SECONDS = 60.0

      DEFAULT_RATE = 44_100

      SID_MODELS = { "6581" => :mos6581, "8580" => :mos8580 }.freeze

      # A Float as OptionParser takes one: digits with an optional sign,
      # fraction and exponent.
      DECIMAL = /\A[-+]?(\d+(\.\d+)?|\.\d+)([eE][-+]?\d+)?\z/

      VALUED = %w[--song -s --sid --frames --screenshot --save-snapshot --audio-out --seconds --songlengths
                  --rate --filter-chunk].freeze

      # The switches and valued options only the window or only the
      # headless player takes.
      WINDOW_ONLY = %w[--no-autostart --read-only --sound --no-sound --no-vsync --verbose --true-drive --frames
                       --unpaced --screenshot --save-snapshot].freeze

      HEADLESS_ONLY = %w[--seconds --songlengths --rate --filter-chunk --quiet --no-tui].freeze

      attr_reader :media, :song, :sid_model, :frames, :screenshot, :save_snapshot, :audio_out, :seconds,
                  :songlengths, :filter_chunk

      def self.parse(argv) = new.parse(argv)

      def initialize
        @media = ""
        @song = nil
        @sid_model = nil
        @autostart = true
        @read_only = false
        @sound = SOUND
        @frames = 0
        @paced = true
        @vsync = true
        @verbose = false
        @true_drive = false
        @screenshot = ""
        @save_snapshot = ""
        @help = false
        @version = false
        @headless = false
        @audio_out = nil
        @seconds = nil
        @songlengths = nil
        @rate = nil
        @filter_chunk = nil
        @quiet = false
        @tui = true
        @window_only = []
        @headless_only = []
      end

      def parse(argv)
        args = argv.dup
        argument(args.shift, args) until args.empty?
        validate unless help? || version?
        self
      end

      # Whether the media is a .vsf snapshot to restore.
      def snapshot? = File.extname(@media).casecmp?(".vsf")

      # Plays or renders a .sid tune without the window.
      def headless? = @headless || render?

      def window? = !headless?

      def render? = !@audio_out.nil?

      # The tune --headless and --audio-out play, for Audio::CLI.
      def tune_path = @media

      # How long to play a tune whose length nothing gives.
      def fallback_seconds = FALLBACK_SECONDS

      def rate = @rate.nil? ? DEFAULT_RATE : @rate

      def rate_given? = !@rate.nil?

      def quiet? = @quiet

      def tui? = @tui

      def autostart? = @autostart

      def read_only? = @read_only

      def sound? = @sound

      def paced? = @paced

      def vsync? = @vsync

      def verbose? = @verbose

      def true_drive? = @true_drive

      def help? = @help

      def version? = @version

      private

      def argument(arg, args)
        if arg == "--"
          media_argument(args.shift) until args.empty?
        elsif arg.start_with?("-") && arg != "-"
          option(arg, args)
        else
          media_argument(arg)
        end
      end

      def option(arg, args)
        name = arg
        value = nil
        if arg.start_with?("--") && arg.include?("=")
          at = arg.index("=")
          name = arg[0, at]
          value = arg[at + 1, arg.size - at - 1]
        end
        restrict(name)
        if VALUED.include?(name)
          value = take_value(name, args) if value.nil?
          valued_option(name, value)
        elsif value.nil?
          switch(name)
        else
          raise Error, "needless argument: #{arg}"
        end
      end

      # Notes an option only the window or only the headless player takes.
      def restrict(name)
        @window_only << name if WINDOW_ONLY.include?(name)
        @headless_only << name if HEADLESS_ONLY.include?(name)
      end

      def take_value(name, args)
        raise Error, "missing argument: #{name}" if args.empty?

        args.shift
      end

      def valued_option(name, value)
        case name
        when "--song", "-s" then @song = number(name, value)
        when "--sid" then @sid_model = sid_model_for(value)
        when "--frames" then @frames = number(name, value)
        when "--screenshot" then @screenshot = value
        when "--save-snapshot" then @save_snapshot = value
        when "--audio-out" then @audio_out = value
        when "--seconds" then @seconds = decimal(name, value)
        when "--songlengths" then @songlengths = value
        when "--rate" then @rate = number(name, value)
        else @filter_chunk = number(name, value)
        end
      end

      def switch(name)
        case name
        when "--no-autostart" then @autostart = false
        when "--read-only" then @read_only = true
        when "--sound" then @sound = true
        when "--no-sound" then @sound = false
        when "--no-vsync" then @vsync = false
        when "--verbose" then @verbose = true
        when "--true-drive" then @true_drive = true
        when "--unpaced" then @paced = false
        when "--help", "-h" then @help = true
        when "--version" then @version = true
        when "--headless" then @headless = true
        when "--quiet" then @quiet = true
        when "--no-tui" then @tui = false
        else raise Error, "invalid option: #{name}"
        end
      end

      def sid_model_for(value)
        raise Error, "invalid argument: --sid #{value}" unless SID_MODELS.key?(value)

        SID_MODELS[value]
      end

      def number(name, value)
        raise Error, "invalid argument: #{name} #{value}" unless value.match?(/\A\d+\z/)

        value.to_i
      end

      def decimal(name, value)
        raise Error, "invalid argument: #{name} #{value}" unless value.match?(DECIMAL)

        value.to_f
      end

      def media_argument(arg)
        raise Error, "unexpected argument: #{arg}" unless @media.empty?

        @media = arg
      end

      def validate
        validate_mode
        validate_numbers
        validate_paths
      end

      def validate_mode
        if headless?
          raise Error, "#{@window_only.first} needs the window" unless @window_only.empty?
          raise Error, "no tune given" if @media.empty?
          raise Error, "not a .sid tune: #{@media}" unless File.extname(@media).casecmp?(".sid")
        elsif !@headless_only.empty?
          raise Error, "#{@headless_only.first} needs --headless or --audio-out"
        end
      end

      def validate_numbers
        positive("--song", @song)
        positive("--seconds", @seconds)
        positive("--rate", @rate)
        positive("--filter-chunk", @filter_chunk)
      end

      def positive(name, value)
        raise Error, "invalid argument: #{name} #{value}" if !value.nil? && value <= 0
      end

      def validate_paths
        raise Error, "no such file or directory: #{@media}" unless @media.empty? || File.exist?(@media)
        raise Error, "no such file or directory: #{@songlengths}" unless @songlengths.nil? || File.exist?(@songlengths)
      end
    end
  end
end
