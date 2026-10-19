# frozen_string_literal: true

module Badline
  class KIM1
    # Pressing the panel's keys in turn, each long enough for the monitor
    # to take it. The monitor takes a key it reads down on two scans in a
    # row, after a scan with no key down, and a scan takes some 4,300
    # cycles, so each key is held for HOLD_CYCLES and let go for
    # RELEASE_CYCLES.
    module KeyEntry
      HOLD_CYCLES = 12_000
      RELEASE_CYCLES = 8_000

      # The panel's keys that type_keys takes by name. Any other word is a
      # run of hex keys.
      NAMED_KEYS = %w[AD DA GO PC + ST RS].freeze

      # Presses the keys `text` names once the monitor is running: AD, DA,
      # GO, PC, + and the hex digits, ST, which pulls NMI, and RS, which
      # resets the machine. Words go by whitespace, and a word that isn't a
      # key's name is a hex key for each of its characters, so
      # "AD 0200 DA A9 +" presses nine keys, and the byte $AD goes in as
      # "A D".
      def type_keys(text)
        keys = text.upcase.split.flat_map { |word| NAMED_KEYS.include?(word) ? [word] : word.chars }
        unknown = keys.find { |key| !NAMED_KEYS.include?(key) && !Panel::KEYS.include?(key) }
        raise ArgumentError, "no KIM-1 key named #{unknown}" unless unknown.nil?

        on_init { queue_keys(keys) }
      end

      # Whether keys type_keys was given are still to be pressed.
      def typing? = !@pending_keys.nil?

      private

      def queue_keys(keys)
        @pending_keys = keys
        @key_down = false
        @next_key_at = @cycles
      end

      def feed_keys
        return if @cycles < @next_key_at

        if @key_down
          release_key
          @key_down = false
          @next_key_at = @cycles + RELEASE_CYCLES
        else
          press_next_key
        end
      end

      def press_next_key
        keys = @pending_keys
        name = keys.shift
        if name.nil?
          @pending_keys = nil
          return
        end
        if name == "ST"
          press_stop
        elsif name == "RS"
          press_reset
        else
          press_key(name)
        end
        @key_down = true
        @next_key_at = @cycles + HOLD_CYCLES
      end
    end
  end
end
