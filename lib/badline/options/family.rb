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

      private

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
      # the C128's, an 8050's or 8250's disk or a PET tape the PET's, and a
      # cartridge signed as a CBM-II's the CBM-II's. A program that loads
      # where PET BASIC starts could be a VIC-20's too.
      def pick_family
        return if @family_named || @sid_command || @media_path.nil? || !File.file?(@media_path)

        if pet_media?
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
