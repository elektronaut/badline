# frozen_string_literal: true

module Badline
  class PET
    class SuperPET < PET
      # The 6702 at $EFE0-$EFE3, the protection chip the Waterloo languages
      # check for. Its behaviour comes from David Roberts' Visual 6702, a
      # switch-level simulation of the decapped chip's netlist, driven a
      # bus cycle at a time.
      #
      # Each data line has a shift register of its own, LENGTHS long, whose
      # first stage the line reads, inverted where INVERTED has the bit
      # set. A latch keeps the last byte written, all ones from the RES
      # line. A write that sets D0 where the last one left it clear shifts
      # every register one stage at the end of the next cycle, whichever
      # cycle that is, so a read in it still finds the old byte. Each
      # register takes in its first stage XORed with the latch's bit,
      # inverted where FEEDBACK has the bit clear, the latch as that cycle
      # leaves it. The RES line clears the registers.
      class Dongle
        LENGTHS = [6, 3, 7, 8, 1, 3, 5, 2].freeze

        INVERTED = 0xd6

        FEEDBACK = 0x29

        # No shift waiting.
        NONE = -1

        # The registers, bit 0 of each the stage its line reads, the latch,
        # and the cycle at whose end the registers shift, or NONE.
        attr_reader :registers, :latch, :shift_at

        # +clock+ answers #cycles, the cycle the CPU's access falls in.
        def initialize(clock)
          @clock = clock
          @registers = Array.new(8, 0)
          reset!
        end

        def reset!
          @registers.fill(0)
          @latch = 0xff
          @shift_at = NONE
        end

        def peek(_addr)
          now = @clock.cycles
          shift if @shift_at != NONE && @shift_at < now
          value = 0
          8.times { |bit| value |= (@registers[bit] & 1) << bit }
          value ^ INVERTED
        end

        def poke(_addr, value)
          now = @clock.cycles
          shift if @shift_at != NONE && @shift_at < now
          raising = value.anybits?(0x01) && @latch.nobits?(0x01)
          @latch = value
          if @shift_at == now
            shift
          elsif raising
            @shift_at = now + 1
          end
        end

        # The registers as they stand once a shift waiting has happened.
        def settled_registers
          registers = @registers.dup
          shift_registers(registers) if @shift_at != NONE
          registers
        end

        private

        def shift
          @shift_at = NONE
          shift_registers(@registers)
        end

        def shift_registers(registers)
          incoming = @latch ^ FEEDBACK ^ 0xff
          8.times do |bit|
            register = registers[bit]
            stage = (register ^ (incoming >> bit)) & 1
            registers[bit] = (register >> 1) | (stage << (LENGTHS[bit] - 1))
          end
        end
      end
    end
  end
end
