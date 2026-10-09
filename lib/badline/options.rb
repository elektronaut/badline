# frozen_string_literal: true

require "badline/options/option"
require "badline/options/event"
require "badline/options/table"
require "badline/options/help"
require "badline/options/validation"
require "badline/options/family"

module Badline
  # The command line of both builds, badline-ruby and the native badline.
  # Either opens the window for any media, or with --headless or
  # --audio-out plays or renders a .sid tune without one. `sid`, given
  # first, plays .sid tunes and directories of them in the terminal.
  # `c64`, `vic20` or `c128`, given first, names the machine family, and
  # without one the family is the C64, or the C128 for a program that loads
  # where C128 BASIC starts. The native build adds --no-sound and
  # --version, and badline-ruby adds --disable-jit.
  #
  # TABLE lists the options, and both the parser and the help read it. It
  # parses by hand, inside the subset of Ruby Spinel compiles. Values come
  # as `--subtune 2` or `--subtune=2`, and `--` ends the options. It loads
  # nothing else from badline, so badline-ruby can parse and reject its
  # arguments before paying for the emulator.
  class Options
    include Validation
    include Family

    class Error < StandardError; end

    FALLBACK_SECONDS = 60.0

    # A tune on the fallback length ends sooner once it has been silent
    # this long.
    SILENCE_SECONDS = 5.0

    SID_MODELS = { "6581" => :mos6581, "8580" => :mos8580 }.freeze

    # What `sid` leaves out besides the window's options.
    NOT_FOR_SID = %w[--audio-out].freeze

    REU_SIZES = %w[128 256 512 1024 2048 4096 8192 16384].freeze

    # The VIC-20's RAM expansions as --ram names them (RAM_NAMES), and the
    # names Vic20::Bus::RAM_CONFIGURATIONS gives them.
    RAM_CONFIGURATIONS = {
      "unexpanded" => :unexpanded, "3k" => :"3k", "8k" => :"8k", "16k" => :"16k", "24k" => :"24k",
      "32k" => :"32k", "all" => :all
    }.freeze

    # A Float as OptionParser took one: digits with an optional sign,
    # fraction and exponent.
    DECIMAL = /\A[-+]?(\d+(\.\d+)?|\.\d+)([eE][-+]?\d+)?\z/

    # tune_paths holds the media given, which `sid` takes more than one of:
    # tunes and directories of tunes, in the order given.
    attr_reader :program, :media_path, :tune_paths, :subtune, :sid_model, :reu, :frames, :screenshot, :save_snapshot,
                :audio_out, :seconds, :songlengths, :filter_chunk, :timeline

    # The machine family to build (Badline::Machine), :c64, :vic20 or
    # :c128.
    attr_reader :family

    # The VIC-20's RAM expansion --ram names, a key of
    # Vic20::Bus::RAM_CONFIGURATIONS, or nil without --ram.
    attr_reader :ram

    def self.parse(argv, native: false) = new(native:).parse(argv)

    # The native build plays the SID in the window unless --no-sound says
    # otherwise, and badline-ruby, which runs below real time, only with
    # --sound.
    def initialize(native: false)
      @native = native
      @program = native ? "badline" : "badline-ruby"
      @media_path = nil
      @family = :c64
      @family_named = false
      @c64_mode = false
      @sid_command = false
      @tune_paths = []
      @subtune = nil
      @sid_model = nil
      @models = []
      @reu = nil
      @ram = nil
      @autostart = true
      @writable = false
      @sound = native
      @frames = 0
      @paced = true
      @vsync = true
      @verbose = false
      @true_drive = false
      @screenshot = ""
      @save_snapshot = ""
      @timeline = []
      @jit = true
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
      @all_subtunes = false
      @window_only = []
      @headless_only = []
    end

    def parse(argv)
      args = argv.dup
      subcommand(args)
      argument(args.shift, args) until args.empty?
      pick_family
      play_lone_tune
      validate unless help? || version?
      self
    end

    # Whether the media is a .vsf snapshot to restore.
    def snapshot? = !@media_path.nil? && File.extname(@media_path).casecmp?(".vsf")

    # Plays or renders a .sid tune without the window.
    def headless? = @headless || render? || @sid_command

    # Whether `sid` came first, to play the tunes and directories given.
    def sid_command? = @sid_command

    # Whether `sid` plays in the SID player's window rather than the
    # terminal.
    def player_window? = @sid_command && !@headless

    def window? = !headless?

    def render? = !@audio_out.nil?

    # The tune --headless and --audio-out play, for Audio::CLI.
    def tune_path = @media_path

    # How long to play a tune whose length nothing gives.
    def fallback_seconds = FALLBACK_SECONDS

    # How long a tune playing for fallback_seconds may stay silent.
    def silence_seconds = SILENCE_SECONDS

    def rate = @rate.nil? ? DEFAULT_RATE : @rate

    def rate_given? = !@rate.nil?

    def quiet? = @quiet

    def tui? = @tui

    def all_subtunes? = @all_subtunes

    def autostart? = @autostart

    def writable? = @writable

    def sound? = @sound

    def paced? = @paced

    def vsync? = @vsync

    def verbose? = @verbose

    def true_drive? = @true_drive

    def jit? = @jit

    # The name of the model to build: a C64 Badline::Model names, a VIC-20
    # of VIC20_MODELS or a C128 of C128_MODELS. --ntsc is short for --model
    # ntsc.
    def model = @models.first || family_models.first

    # Whether --c64 asks the C128 to start in C64 mode, holding C= at
    # power-on.
    def c64_mode? = @c64_mode

    def help? = @help

    def version? = @version

    private

    def takes?(option)
      return false if @sid_command && (option.needs == :window || NOT_FOR_SID.include?(option.name))

      [:both, @native ? :native : :ruby].include?(option.build)
    end

    # A .sid on its own plays in the SID player, as `sid` would, unless an
    # option of the emulator's window asks for the machine.
    def play_lone_tune
      return if @sid_command || @family == :vic20 || headless? || !@window_only.empty? || @media_path.nil?

      @sid_command = File.extname(@media_path).casecmp?(".sid")
    end

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
      flag = arg.start_with?("--") && arg.include?("=") ? arg[0, arg.index("=")] : arg
      option = find(flag)
      restrict(option, flag)
      if flag == arg
        option.valued? ? valued_option(option.name, flag, take_value(flag, args)) : switch(option.name)
      elsif option.valued?
        valued_option(option.name, flag, arg[flag.size + 1, arg.size - flag.size - 1])
      else
        raise Error, "needless argument: #{arg}"
      end
    end

    def find(flag)
      option = TABLE.find { |candidate| candidate.named?(flag) && takes?(candidate) }
      raise Error, "invalid option: #{flag}" if option.nil?

      option
    end

    # Notes an option only the window or only the headless player takes.
    def restrict(option, flag)
      @window_only << flag if option.needs == :window
      @headless_only << flag if option.needs == :headless
    end

    def take_value(flag, args)
      raise Error, "missing argument: #{flag}" if args.empty?

      args.shift
    end

    def valued_option(name, flag, value)
      case name
      when "--subtune" then @subtune = number(flag, value)
      when "--sid" then @sid_model = sid_model_for(value)
      when "--model" then @models << value
      when "--reu" then @reu = reu_size(value)
      when "--ram" then @ram = ram_configuration(value)
      when "--frames" then @frames = number(flag, value)
      when "--screenshot" then @screenshot = value
      when "--save-snapshot" then @save_snapshot = value
      when "--at", "--script" then @timeline.concat(Event.given(name, value))
      when "--audio-out" then @audio_out = value
      when "--seconds" then @seconds = decimal(flag, value)
      when "--songlengths" then @songlengths = value
      when "--rate" then @rate = number(flag, value)
      else @filter_chunk = number(flag, value)
      end
    end

    def switch(name)
      case name
      when "--no-autostart" then @autostart = false
      when "--writable" then @writable = true
      when "--sound" then @sound = true
      when "--no-sound" then @sound = false
      when "--no-vsync" then @vsync = false
      when "--verbose" then @verbose = true
      when "--true-drive" then @true_drive = true
      when "--ntsc" then @models << "ntsc"
      when "--c64" then @c64_mode = true
      when "--unpaced" then @paced = false
      when "--disable-jit" then @jit = false
      when "--help" then @help = true
      when "--version" then @version = true
      when "--headless" then @headless = true
      when "--quiet" then @quiet = true
      when "--all-subtunes" then @all_subtunes = true
      else @tui = false
      end
    end

    def media_argument(arg)
      raise Error, "unexpected argument: #{arg}" unless @sid_command || @media_path.nil?

      @media_path = arg if @media_path.nil?
      @tune_paths << arg
    end
  end
end
