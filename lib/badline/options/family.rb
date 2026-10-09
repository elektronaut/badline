# frozen_string_literal: true

require "badline/storage/p00"

module Badline
  class Options
    # The machine family: the subcommand that names it, or else the media,
    # and the models of each.
    module Family
      # Where C128 BASIC starts, which a program for the C128 loads at.
      C128_BASIC_START = 0x1c01

      private

      # Takes `sid`, `c64`, `vic20` or `c128` when given first.
      def subcommand(args)
        case args.first
        when "sid" then @sid_command = true
        when "c64" then @family = :c64
        when "vic20" then @family = :vic20
        when "c128" then @family = :c128
        else return
        end
        @family_named = !@sid_command
        args.shift
      end

      def family_models
        case @family
        when :vic20 then VIC20_MODELS
        when :c128 then C128_MODELS
        else MODELS
        end
      end

      # Without a family named, a program that loads at C128_BASIC_START is
      # the C128's.
      def pick_family
        return if @family_named || @sid_command || @media_path.nil?
        return unless %w[.prg .p00].include?(File.extname(@media_path).downcase) && File.file?(@media_path)

        @family = :c128 if Storage::P00.load_address(@media_path) == C128_BASIC_START
      end
    end
  end
end
