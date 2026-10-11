# frozen_string_literal: true

module Badline
  class Cartridge
    class RetroReplay < Cartridge
      # A Retro Replay's registers, RAM and flash, for a snapshot.
      module SavedState
        private

        def save_jumpers(out)
          out.boolean(true).boolean(@flash_jumper).boolean(@bank_jumper)
        end

        def save_mapper(out)
          [@active, @frozen, @phi1_ultimax, @ram_enabled, @ram_at_a000, @allow_bank, @no_freeze, @reu_mapping,
           @write_once].each { |flag| out.boolean(flag) }
          out.int(@bank).int(RetroReplay::CONTROL_MODES.index(@config))
          @ram_data.each { |data| out.blob(data) }
          @flash.save_state(out)
        end

        def load_mapper(input)
          load_flags(input)
          @bank = input.int
          @config = RetroReplay::CONTROL_MODES.fetch(input.int)
          @ram_data.each { |data| input.blob_into(data) }
          @flash.load_state(input)
          map_windows
        end

        def load_flags(input)
          @active = input.boolean?
          @frozen = input.boolean?
          @phi1_ultimax = input.boolean?
          @ram_enabled = input.boolean?
          @ram_at_a000 = input.boolean?
          @allow_bank = input.boolean?
          @no_freeze = input.boolean?
          @reu_mapping = input.boolean?
          @write_once = input.boolean?
        end
      end
    end
  end
end
