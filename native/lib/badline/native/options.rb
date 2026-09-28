# frozen_string_literal: true

module Badline
  module Native
    # The command line of the native badline: badline-ruby's window options
    # (--sound, --sid, --song, --no-autostart, --read-only, --help) plus
    # --version and the testing knobs --frames, --unpaced and --screenshot.
    # Spinel has no OptionParser, so it parses by hand. Values come as
    # `--song 2` or `--song=2`, and `--` ends the options.
    class Options
      class Error < StandardError; end

      # Whether the SID plays unless --sound or --no-sound says otherwise.
      SOUND = true

      SID_MODELS = { "6581" => :mos6581, "8580" => :mos8580 }.freeze

      VALUED = %w[--song -s --sid --frames --screenshot].freeze

      HELP = <<~HELP.freeze
        Usage: badline [options] [media]

        Media can be a .prg/.p00 program, a .d64/.d71/.d81 disk image,
        a .t64 tape archive, a .tap tape, a .crt cartridge, a .sid tune, or
        a directory to mount as device 8.

        Options:
            -s, --song N                     Subtune of a .sid, from 1 (default: the tune's own)
                --sid MODEL                  SID to fit: 6581 or 8580 (default: a .sid tune's own, else 6581)
                --no-autostart               Boot to READY. instead of running the program
                --read-only                  Mount a disk image write-protected, leaving its file unchanged
                --sound                      Play the SID through the host's audio device (F10 mutes)#{' (default)' if SOUND}
                --no-sound                   Don't play the SID#{' (default)' unless SOUND}
                --no-vsync                   Pace PAL frames by the timer or the sound instead of the display
            -h, --help                       Show this help
                --version                    Show the version and what built it

        Testing options:
                --frames N                   Quit after N frames
                --unpaced                    Run as fast as it can, without vsync or pacing
                --screenshot FILE            Save the last frame as a .bmp
      HELP

      attr_reader :media, :song, :sid_model, :frames, :screenshot

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
        @screenshot = ""
        @help = false
        @version = false
      end

      def parse(argv)
        args = argv.dup
        argument(args.shift, args) until args.empty?
        validate unless help? || version?
        self
      end

      def autostart? = @autostart

      def read_only? = @read_only

      def sound? = @sound

      def paced? = @paced

      def vsync? = @vsync

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
        if VALUED.include?(name)
          value = take_value(name, args) if value.nil?
          valued_option(name, value)
        elsif value.nil?
          switch(name)
        else
          raise Error, "needless argument: #{arg}"
        end
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
        else @screenshot = value
        end
      end

      def switch(name)
        case name
        when "--no-autostart" then @autostart = false
        when "--read-only" then @read_only = true
        when "--sound" then @sound = true
        when "--no-sound" then @sound = false
        when "--no-vsync" then @vsync = false
        when "--unpaced" then @paced = false
        when "--help", "-h" then @help = true
        when "--version" then @version = true
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

      def media_argument(arg)
        raise Error, "unexpected argument: #{arg}" unless @media.empty?

        @media = arg
      end

      def validate
        raise Error, "invalid argument: --song #{@song}" if !@song.nil? && @song < 1
        raise Error, "no such file or directory: #{@media}" unless @media.empty? || File.exist?(@media)
      end
    end
  end
end
