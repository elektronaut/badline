# frozen_string_literal: true

module Badline
  module Frontend
    # The host's keys on a PET's key matrix, by the character each types
    # (Keys.pet_key), so the host's " types the PET's " on either keyboard.
    #
    # The PET's SHIFT follows the host's, except while a key down needs it
    # one way to type its character: then it is held that way until the
    # key goes up, the last such key deciding.
    class PETKeyboard
      LSHIFT = 225
      RSHIFT = 229

      # +layout+ is the PET's keyboard, :graphics or :business.
      def initialize(keyboard, layout)
        @keyboard = keyboard
        @layout = layout
        @held = {}
        @left_shift = false
        @right_shift = false
        @forced = -1
        @forced_shift = false
      end

      def key(scancode, down)
        if [LSHIFT, RSHIFT].include?(scancode)
          shift_key(scancode, down)
        elsif down
          key_down(scancode)
        else
          key_up(scancode)
        end
      end

      # Lets go of every key, SHIFT among them.
      def release_all
        @held.each_value { |key| @keyboard.release(key) }
        @held = {}
        @left_shift = false
        @right_shift = false
        @forced = -1
        sync_shift
      end

      private

      def key_down(scancode)
        key_up(scancode) if @held.key?(scancode)
        key, shift = Keys.pet_key(scancode, shifted?, @layout)
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

      def shifted? = @left_shift || @right_shift

      def sync_shift
        shift = @forced == -1 ? shifted? : @forced_shift
        @keyboard.release(:lshift)
        @keyboard.press(:lshift) if shift
      end
    end
  end
end
