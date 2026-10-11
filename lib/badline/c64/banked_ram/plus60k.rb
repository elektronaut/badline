# frozen_string_literal: true

module Badline
  class C64
    module BankedRAM
      # The +60K: a second bank of RAM behind $1000-$FFFF, selected by bit 7
      # of $D100. $0000-$0FFF stays the machine's own RAM, and so does all of
      # what the VIC sees.
      class Plus60k
        include Banking

        def initialize(ram)
          @low_ram = @video_ram = @high_ram = ram
          @banks = [ram, Memory.new]
          @on_change = nil
        end

        def poke(_addr, value)
          @high_ram = @banks[value >> 7]
          @on_change&.call
        end

        def reset!
          @high_ram = @banks[0]
        end

        def type = :plus60k

        def save_state(out)
          out.int(@banks.index(@high_ram))
          @banks[1].save_state(out)
        end

        def load_state(input)
          @high_ram = @banks.fetch(input.int)
          @banks[1].load_state(input)
        end

        # $D100 as bit 7 picks the bank above $1000, and bank 1, in a
        # keyed snapshot module.
        def save_fields(out)
          out.int("d100", @banks.index(@high_ram).to_i << 7)
          @banks[1].save_fields(out, "bank1")
        end

        def load_fields(input)
          @high_ram = @banks[(input.byte("d100", @banks.index(@high_ram).to_i << 7) >> 7) & 1]
          @banks[1].load_fields(input, "bank1")
        end

        def power_on!
          @banks[1].clear!
        end
      end
    end
  end
end
