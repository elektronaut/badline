# frozen_string_literal: true

require "badline/storage/crt_file"
require "badline/storage/p00"
require "badline/storage/tap"

module Badline
  class Options
    # The machine family: the subcommand that names it, or else the media,
    # and the models of each.
    module Family
      # Where C128 BASIC starts, which a program for the C128 loads at.
      C128_BASIC_START = 0x1c01

      # Whether the KIM-1 talks to a teletype: with --tty or --tty-load,
      # and always on the terminal with --headless.
      def tty? = @tty || @tty_load || kim1_terminal?

      # The KIM-1 teletype's baud.
      def baud = @baud

      # Whether the KIM-1 loads a papertape through its monitor's L
      # command, with --tty-load.
      def tty_load? = @tty_load

      # Where the KIM-1 loads a .bin, and where it starts its program, as
      # --load-address and --start-address give them, or nil.
      def load_address = @load_address

      def start_address = @start_address

      # Whether the KIM-1 runs on the terminal, its teletype there.
      def kim1_terminal? = @family == :kim1 && @headless

      private

      # The KIM-1's keypad, until --tty or --baud name its teletype, and
      # its programs where they load.
      def initialize_kim1
        @tty = false
        @tty_load = false
        @baud = 9600
        @load_address = nil
        @start_address = nil
      end

      # The KIM-1 teletype's baud, and where it loads a .bin and starts a
      # program.
      def kim1_option(name, flag, value)
        case name
        when "--baud" then @baud = baud_for(value)
        when "--load-address" then @load_address = address(flag, value)
        else @start_address = address(flag, value)
        end
      end

      def kim1_switch(name)
        if name == "--tty"
          @tty = true
        else
          @tty_load = true
        end
      end

      # An address in hex, with or without a $ or 0x before it.
      def address(flag, value)
        digits = value.delete_prefix("$").delete_prefix("0x").delete_prefix("0X")
        raise Error, "invalid argument: #{flag} #{value}" unless digits.match?(/\A[0-9a-fA-F]{1,4}\z/)

        digits.to_i(16)
      end

      def kim1_ram(value)
        raise Error, "invalid argument: --ram #{value}" unless KIM1_RAM.key?(value)

        KIM1_RAM[value]
      end

      # The KIM-1 runs in the window, or with --headless on the terminal,
      # without the C64's SID and REU. Only a papertape goes in through
      # the teletype, and only a .bin has a load address to give.
      def validate_kim1
        raise Error, "--ntsc needs the C64" if @models.include?("ntsc")
        raise Error, "--sid needs the C64" unless @sid_model.nil?
        raise Error, "--reu needs the C64" unless @reu.nil?
        raise Error, "--audio-out needs a .sid tune" unless @audio_out.nil?

        extension = @media_path.nil? ? "" : File.extname(@media_path).downcase
        raise Error, "--tty-load needs a .ptp or .pap" if @tty_load && !%w[.ptp .pap].include?(extension)
        raise Error, "--load-address needs a .bin" unless @load_address.nil? || extension == ".bin"
      end

      # Only the KIM-1 has a teletype, and programs without a load address.
      def refuse_kim1_options
        raise Error, "#{@tty ? '--tty' : '--baud'} needs kim1" if @tty || @baud != 9600
        raise Error, "--tty-load needs kim1" if @tty_load
        raise Error, "--load-address needs kim1" unless @load_address.nil?
        raise Error, "--start-address needs kim1" unless @start_address.nil?
      end

      # Takes `sid`, `c64`, `vic20`, `c128`, `plus4`, `pet`, `cbm2` or `kim1`
      # when given first.
      def subcommand(args)
        case args.first
        when "sid" then @sid_command = true
        when "c64" then @family = :c64
        when "vic20" then @family = :vic20
        when "c128" then @family = :c128
        when "plus4" then @family = :plus4
        when "pet" then @family = :pet
        when "cbm2" then @family = :cbm2
        when "kim1" then @family = :kim1
        else return
        end
        @family_named = !@sid_command
        args.shift
      end

      def family_models
        case @family
        when :vic20 then VIC20_MODELS
        when :c128 then C128_MODELS
        when :plus4 then PLUS4_MODELS
        when :pet then PET_MODELS
        when :cbm2 then CBM2_MODELS
        when :kim1 then KIM1_MODELS
        else MODELS
        end
      end

      # Without a family named, a program that loads at C128_BASIC_START is
      # the C128's, an 8050's or 8250's disk or a PET tape the PET's, a
      # cartridge signed as a CBM-II's the CBM-II's, and a papertape the
      # KIM-1's. A program that loads where PET BASIC starts could be a
      # VIC-20's too.
      def pick_family
        return if @family_named || @sid_command || @media_path.nil? || !File.file?(@media_path)

        if Media::Extensions.kind(@media_path) == :papertape
          @family = :kim1
        elsif pet_media?
          @family = :pet
        elsif cbm2_cartridge?
          @family = :cbm2
        elsif Media::Extensions::PROGRAMS.include?(File.extname(@media_path).downcase)
          @family = :c128 if Storage::P00.load_address(@media_path) == C128_BASIC_START
        end
      end

      # Whether the media is a cartridge signed as a CBM-II's.
      def cbm2_cartridge?
        Media::Extensions.kind(@media_path) == :cartridge && Storage::CRTFile.cbm2?(@media_path)
      end

      # Whether the media is an 8050's or 8250's disk, a D9060's or D9090's
      # hard disk, or a PET tape.
      def pet_media?
        kind = Media::Extensions.kind(@media_path)
        %i[ieee_disk hard_disk].include?(kind) || (kind == :tape && Storage::TAP.platform_of(@media_path) == Storage::TAP::PET_PLATFORM)
      end
    end
  end
end
