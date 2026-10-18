# frozen_string_literal: true

module Badline
  module Frontend
    # The host's keys on a PET's key matrix, by the character each types
    # (Keys.pet_key), so the host's " types the PET's " on either keyboard.
    #
    # The PET's SHIFT follows the host's, except while a key down needs it
    # one way to type its character: then it is held that way until the
    # key goes up, the last such key deciding.
    #
    # With either Alt down, a key that types a character presses the PET
    # key its unshifted character is on with the PET's SHIFT, so the
    # graphics on the graphics keyboard's symbol keys can be typed.
    #
    # The CBM-II's keyboard goes the same way (Keys.cbm2_key), and there
    # Alt with a key presses one of the keys the host has none for
    # (Keys.cbm2_alt_key).
    class PETKeyboard
      LSHIFT = 225
      RSHIFT = 229
      LALT = 226
      RALT = 230

      # +layout+ is the PET's keyboard, :graphics or :business, or :cbm2
      # for the CBM-II's.
      def initialize(keyboard, layout)
        @keyboard = keyboard
        @layout = layout
        @shift = layout == :cbm2 ? :shift : :lshift
        @held = {}
        @left_shift = false
        @right_shift = false
        @left_alt = false
        @right_alt = false
        @forced = -1
        @forced_shift = false
      end

      def key(scancode, down)
        if [LSHIFT, RSHIFT].include?(scancode)
          shift_key(scancode, down)
        elsif [LALT, RALT].include?(scancode)
          alt_key(scancode, down)
        elsif down
          key_down(scancode)
        else
          key_up(scancode)
        end
      end

      # Whether a key the scancode pressed is still down.
      def holds?(scancode) = @held.key?(scancode)

      def alt? = @left_alt || @right_alt

      # Lets go of every key, SHIFT among them.
      def release_all
        @held.each_value { |key| @keyboard.release(key) }
        @held = {}
        @left_shift = false
        @right_shift = false
        @left_alt = false
        @right_alt = false
        @forced = -1
        sync_shift
      end

      private

      def key_down(scancode)
        key_up(scancode) if @held.key?(scancode)
        key, shift = alt? ? shifted_key(scancode) : layout_key(scancode, shifted?)
        return if key == :none

        unless shift == :host
          @forced = scancode
          @forced_shift = shift == :on
        end
        sync_shift
        @held[scancode] = key
        @keyboard.press(key)
      end

      def key_up(scancode)
        key = @held.delete(scancode)
        return if key.nil?

        @keyboard.release(key)
        return unless @forced == scancode

        @forced = -1
        sync_shift
      end

      def shift_key(scancode, down)
        if scancode == LSHIFT
          @left_shift = down
        else
          @right_shift = down
        end
        sync_shift
      end

      def alt_key(scancode, down)
        if scancode == LALT
          @left_alt = down
        else
          @right_alt = down
        end
      end

      def layout_key(scancode, shift)
        @layout == :cbm2 ? Keys.cbm2_key(scancode, shift) : Keys.pet_key(scancode, shift, @layout)
      end

      # The PET key for the scancode with Alt down: for a letter or a key
      # that types a character, the key its unshifted character is on, with
      # SHIFT, and for any other key the one it presses without Alt. The
      # CBM-II's is the one Keys.cbm2_alt_key names.
      def shifted_key(scancode)
        return Keys.cbm2_alt_key(scancode) if @layout == :cbm2

        key, shift = Keys.pet_key(scancode, false, @layout)
        return [key, shift] if key == :none
        return [key, shift] unless scancode.between?(4, 29) || Keys::US_CHARACTERS.key?(scancode)

        [key, :on]
      end

      def shifted? = @left_shift || @right_shift

      def sync_shift
        shift = @forced == -1 ? shifted? : @forced_shift
        @keyboard.release(@shift)
        @keyboard.press(@shift) if shift
      end
    end
  end
end
