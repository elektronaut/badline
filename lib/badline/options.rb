# frozen_string_literal: true

require "badline/pet/rom_sets"
require "badline/drives/ieee_models"
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
  # `c64`, `vic20`, `c128`, `plus4`, `pet` or `cbm2`, given first, names
  # the machine family, and without one the family is the C64, the C128
  # for a program that loads where C128 BASIC starts, the PET for an
  # 8050's or 8250's disk or a PET tape, or the CBM-II for a cartridge
  # signed as its own. `kim1` runs a MOS KIM-1.
  # The native build adds --no-sound and --version, and badline-ruby adds
  # --disable-jit.
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
    NOT_FOR_SID = %w[--audio-out --tty --baud].freeze

    REU_SIZES = %w[128 256 512 1024 2048 4096 8192 16384].freeze

    # The VIC-20's RAM expansions as --ram names them (RAM_NAMES), and the
    # names Vic20::Bus::RAM_CONFIGURATIONS gives them.
    RAM_CONFIGURATIONS = {
      "unexpanded" => :unexpanded, "3k" => :"3k", "8k" => :"8k", "16k" => :"16k", "24k" => :"24k",
      "32k" => :"32k", "all" => :all
    }.freeze

    # The Plus/4's RAM sizes as --ram names them, in K.
    PLUS4_RAM = { "16k" => 16, "32k" => 32, "64k" => 64 }.freeze

    # The PET's, below $8000.
    PET_RAM = { "4k" => 4, "8k" => 8, "16k" => 16, "32k" => 32 }.freeze

    # Where --sid-card-address puts the Plus/4's SID card.
    SID_CARD_ADDRESSES = { "fd40" => 0xfd40, "fe80" => 0xfe80 }.freeze

    # The Plus/4's RAM expansions as --ram-expansion names them.
    PLUS4_RAM_EXPANSIONS = { "hannes256" => :hannes256, "hannes1m" => :hannes1m, "csory256" => :csory256 }.freeze

    # The Plus/4's cartridge slots, by the options that fill them and
    # xplus4's names (Media::Plus4Media::SLOTS).
    CARTRIDGE_SLOTS = { "--c1lo" => "c1lo", "--c1hi" => "c1hi", "--c2lo" => "c2lo", "--c2hi" => "c2hi" }.freeze

    # A Float as OptionParser took one: digits with an optional sign,
    # fraction and exponent.
    DECIMAL = /\A[-+]?(\d+(\.\d+)?|\.\d+)([eE][-+]?\d+)?\z/

    # tune_paths holds the media given, which `sid` takes more than one of:
    # tunes and directories of tunes, in the order given.
    attr_reader :program, :media_path, :tune_paths, :subtune, :sid_model, :reu, :frames, :screenshot, :save_snapshot,
                :audio_out, :seconds, :songlengths, :filter_chunk, :timeline

    # The machine family to build (Badline::Machine), :c64, :vic20, :c128,
    # :plus4, :pet or :cbm2.
    attr_reader :family

    # The ROMs --basic, --editor and --characters fit a PET with, keys of
    # PET::ROMSets::BASICS, PET::ROMSets::EDITORS and
    # PET::ROMSets::CHARACTERS, or nil for its own.
    attr_reader :basic, :editor, :characters

    # The 8296's board jumpers --jumpers names (PET::Bus::Expansion::JUMPERS).
    attr_reader :jumpers

    # The SuperPET's CPU switch, as --cpu sets it: "6502", "6809" or
    # "prog".
    def cpu = @cpu || "6502"

    # The SuperPET's bank RAM switch, as --bank-ram sets it: "rw", "read"
    # or "prog".
    def bank_ram = @bank_ram || "rw"

    # The VIC-20's RAM expansion --ram names, a key of
    # Vic20::Bus::RAM_CONFIGURATIONS, or nil without --ram.
    attr_reader :ram

    # The Plus/4's or the PET's RAM in K --ram names, one of PLUS4_RAM's or
    # PET_RAM's, or nil without --ram.
    attr_reader :ram_kb

    # The Plus/4's cartridge ROM images --c1lo, --c1hi, --c2lo and --c2hi
    # name, by slot: { "c1lo" => path }.
    attr_reader :cartridges

    # The SID model of the Plus/4's SID card --sid-card names, :mos6581 or
    # :mos8580, or nil without one.
    attr_reader :sid_card

    # Where --sid-card-address puts the Plus/4's SID card, $FD40 without
    # it.
    attr_reader :sid_card_address

    # The Plus/4's RAM expansion --ram-expansion names, a key of
    # Plus4::RAMExpansion::KINDS, or nil without one.
    attr_reader :ram_expansion

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
      @sid_card = nil
      @sid_card_address = nil
      @ram_expansion = nil
      @models = []
      @reu = nil
      @ram = nil
      @ram_kb = nil
      @ram_name = nil
      initialize_pet
      initialize_kim1
      @kernal = nil
      @cartridges = {}
      @autostart = true
      @writable = false
      @sound = native
      @frames = 0
      @paced = true
      @vsync = true
      @verbose = false
      @true_drive = false
      @drive_type = nil
      @screenshot = ""
      @save_snapshot = ""
      @vice = false
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
      @any_window_only = []
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

    def true_drive? = @true_drive || !@drive_type.nil?

    # The true drive --drive-type names: without it, "1551" on the Plus/4
    # and the 2031 on the PET and the CBM-II.
    def drive_type = @drive_type || (@family == :plus4 ? "1551" : Drives::IEEEModels::DEFAULT)

    # Whether --save-snapshot adds VICE's modules, so x64sc opens it.
    def vice? = @vice

    def jit? = @jit

    # The name of the model to build: a C64 Badline::Model names, a VIC-20
    # of VIC20_MODELS, a C128 of C128_MODELS or a Plus/4 of PLUS4_MODELS.
    # --ntsc is short for --model ntsc.
    def model = @models.first || family_models.first

    # Whether --c64 asks the C128 to start in C64 mode, holding C= at
    # power-on.
    def c64_mode? = @c64_mode

    # The frame rate of a CRTC PET's editor: 60 with --60hz or a 60 Hz
    # --editor, else 50. A B series CBM-II's mains, which its editor
    # follows.
    def refresh_hz = @refresh_hz || 50

    # The CBM-II's mains, 60 with --60hz, or nil for the model's own.
    def mains_hz = @refresh_hz

    # The CBM-II's KERNAL --kernal names, one of CBM2_KERNALS or, on the
    # P500, P500_KERNALS, the first of them without it.
    def kernal = @kernal || (p500? ? P500_KERNALS : CBM2_KERNALS).first

    # Whether the CBM-II to run is a P500, a 510 of either region.
    def p500? = @family == :cbm2 && model.start_with?("510")

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
      return if @sid_command || %i[vic20 plus4 pet cbm2 kim1].include?(@family) || headless? || !@window_only.empty?
      return if @media_path.nil?

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

    # Notes an option only the window, only a window of either kind, or
    # only the headless player takes.
    def restrict(option, flag)
      @window_only << flag if option.needs == :window
      @any_window_only << flag if option.needs == :any_window
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
      when "--sid-card" then @sid_card = sid_card_for(value)
      when "--sid-card-address" then @sid_card_address = sid_card_address_for(value)
      when "--ram-expansion" then @ram_expansion = plus4_ram_expansion(value)
      when "--model" then @models << value
      when "--reu" then @reu = reu_size(value)
      when "--ram" then @ram_name = value
      when "--basic", "--editor", "--characters", "--jumpers", "--cpu", "--bank-ram" then pet_option(name, value)
      when "--drive-type" then @drive_type = drive_type_for(value)
      when "--kernal" then @kernal = kernal_for(value)
      when "--c1lo", "--c1hi", "--c2lo", "--c2hi" then @cartridges[CARTRIDGE_SLOTS.fetch(name)] = value
      when "--frames" then @frames = number(flag, value)
      when "--screenshot" then @screenshot = value
      when "--save-snapshot" then @save_snapshot = value
      when "--at", "--script" then @timeline.concat(Event.given(name, value))
      when "--audio-out" then @audio_out = value
      when "--seconds" then @seconds = decimal(flag, value)
      when "--songlengths" then @songlengths = value
      when "--rate" then @rate = number(flag, value)
      when "--baud" then @baud = baud_for(value)
      else @filter_chunk = number(flag, value)
      end
    end

    # The PET's frame rate, ROMs, board jumpers and the SuperPET's CPU and
    # bank RAM switches, its own until named.
    def initialize_pet
      @cpu = nil
      @bank_ram = nil
      @refresh_hz = nil
      @basic = nil
      @editor = nil
      @characters = nil
      @jumpers = []
    end

    def pet_option(name, value)
      case name
      when "--basic" then @basic = value
      when "--editor" then @editor = value
      when "--characters" then @characters = value
      when "--cpu" then @cpu = value
      when "--bank-ram" then @bank_ram = value
      else @jumpers = value.split(",")
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
      when "--vice" then @vice = true
      when "--ntsc" then @models << "ntsc"
      when "--c64" then @c64_mode = true
      when "--60hz" then @refresh_hz = 60
      when "--unpaced" then @paced = false
      when "--disable-jit" then @jit = false
      when "--help" then @help = true
      when "--version" then @version = true
      when "--headless" then @headless = true
      when "--quiet" then @quiet = true
      when "--all-subtunes" then @all_subtunes = true
      when "--tty" then @tty = true
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
