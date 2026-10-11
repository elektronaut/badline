# frozen_string_literal: true

module Badline
  class C64
    module BankedRAM
      # The +256K: four 64K banks, the first of them the machine's own RAM.
      # $D100 picks one for $0000-$0FFF (bits 0-1), one for the VIC (bits 2-3)
      # and one for $1000-$FFFF (bits 6-7). Setting bit 4 locks the register
      # until the next reset.
      class Plus256k
        include Banking

        def initialize(ram)
          @banks = [ram, Memory.new, Memory.new, Memory.new]
          @on_change = nil
          reset!
        end

        def poke(_addr, value)
          return if @locked

          @low_ram = @banks[value & 0b11]
          @video_ram = @banks[(value >> 2) & 0b11]
          @high_ram = @banks[value >> 6]
          @locked = value.anybits?(0x10)
          @on_change&.call
        end

        def reset!
          @low_ram = @video_ram = @high_ram = @banks[0]
          @locked = false
        end

        def type = :plus256k

        def save_state(out)
          [@low_ram, @video_ram, @high_ram].each { |bank| out.int(@banks.index(bank)) }
          out.boolean(@locked)
          @banks.drop(1).each { |bank| bank.save_state(out) }
        end

        def load_state(input)
          @low_ram = @banks.fetch(input.int)
          @video_ram = @banks.fetch(input.int)
          @high_ram = @banks.fetch(input.int)
          @locked = input.boolean?
          @banks.drop(1).each { |bank| bank.load_state(input) }
        end

        # $D100 as the banks it picks give it, whether it is locked, and
        # banks 1 to 3, in a keyed snapshot module.
        def save_fields(out)
          low = @banks.index(@low_ram).to_i
          video = @banks.index(@video_ram).to_i
          out.int("d100", low | (video << 2) | (@banks.index(@high_ram).to_i << 6)).bool("locked", @locked)
          @banks[1].save_fields(out, "bank1")
          @banks[2].save_fields(out, "bank2")
          @banks[3].save_fields(out, "bank3")
        end

        def load_fields(input)
          value = input.byte("d100", 0)
          @low_ram = @banks[value & 0b11]
          @video_ram = @banks[(value >> 2) & 0b11]
          @high_ram = @banks[value >> 6]
          @locked = input.bool("locked", @locked)
          @banks[1].load_fields(input, "bank1")
          @banks[2].load_fields(input, "bank2")
          @banks[3].load_fields(input, "bank3")
        end

        def power_on!
          @banks.drop(1).each(&:clear!)
        end
      end
    end
  end
end
