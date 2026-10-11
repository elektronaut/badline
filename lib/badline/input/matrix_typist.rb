# frozen_string_literal: true

module Badline
  module Input
    # Types PETSCII codes on a Keyboard's matrix, one key at a time, for
    # software that scans the keys itself instead of reading a KERNAL's
    # keyboard buffer: each code's keys go down for HOLD cycles, then up for
    # GAP cycles. Codes it has no key for are skipped.
    class MatrixTypist
      HOLD = 100_000
      GAP = 40_000

      # The keys typed without SHIFT, by PETSCII code.
      PLAIN = {
        0x0d => :return, 0x20 => :space, 0x2a => :*, 0x2b => :+, 0x2c => :",", 0x2d => :-, 0x2e => :".",
        0x2f => :/, 0x3a => :":", 0x3b => :";", 0x3d => :"=", 0x40 => :"@"
      }.freeze

      # The keys typed with SHIFT, by PETSCII code.
      SHIFTED = {
        0x21 => :"1", 0x22 => :"2", 0x23 => :"3", 0x24 => :"4", 0x25 => :"5", 0x26 => :"6", 0x27 => :"7",
        0x28 => :"8", 0x29 => :"9", 0x3c => :",", 0x3e => :".", 0x3f => :/, 0x5b => :":", 0x5d => :";"
      }.freeze

      DIGITS = %i[0 1 2 3 4 5 6 7 8 9].freeze
      LETTERS = %i[a b c d e f g h i j k l m n o p q r s t u v w x y z].freeze

      # The keys that type the PETSCII code, SHIFT first, or none.
      def self.keys(code)
        return [DIGITS[code - 0x30]] if code.between?(0x30, 0x39)
        return [LETTERS[code - 0x41]] if code.between?(0x41, 0x5a)
        return [:lshift, LETTERS[code - 0xc1]] if code.between?(0xc1, 0xda)
        return [PLAIN[code]] if PLAIN.key?(code)
        return [:lshift, SHIFTED[code]] if SHIFTED.key?(code)

        []
      end

      def initialize(keyboard)
        @keyboard = keyboard
        @held = []
        @wait = 0
        @typing = false
      end

      # Whether it is part way through codes: from the first key down until
      # the last one is up and its gap has passed.
      def typing? = @typing

      # A cycle of typing +codes+, taking each code off its front as its keys
      # go down.
      def cycle!(codes)
        @wait -= 1 if @wait.positive?
        return unless @wait.zero?

        if @held.empty?
          press(codes)
        else
          @held.each { |key| @keyboard.release(key) }
          @held = []
          @wait = GAP
        end
      end

      private

      def press(codes)
        @typing = !codes.empty?
        return unless @typing

        @held = MatrixTypist.keys(codes.shift)
        @held.each { |key| @keyboard.press(key) }
        @wait = @held.empty? ? 1 : HOLD
      end
    end
  end
end
