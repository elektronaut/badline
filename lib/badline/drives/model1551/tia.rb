# frozen_string_literal: true

module Badline
  module Drives
    class Model1551
      # The drive's 6523 TIA at $4000-$7FFF, its eight registers mirrored
      # (zimmers.net's 1551 memory map, schematic 251860):
      #
      # - Port A carries the cable's eight data lines, pulled up.
      # - Port B reads the GCR byte the gate array latched at BYTE READY
      #   and drives the byte the head writes.
      # - Port C drives STATUS0 and STATUS1 (PC0-1), DEV (PC2), which picks
      #   where the computer's TIA answers, ACK (PC3) and the head's MODE
      #   (PC4, low to write), and reads the device number jumper (PC5,
      #   high for device 9), SYNC (PC6, low in a SYNC mark) and DAV (PC7).
      #
      # The DOS sets port C's directions to $1F. The cable's lines are
      # pulled up, so an input nothing drives reads 1.
      #
      # Any access to the TIA clears BYTE LATCHED.
      class TIA < Chips::TIA
        DAV = 0x80
        SYNC = 0x40
        JUMPER = 0x20
        MODE = 0x10

        def initialize(mechanism, device:)
          @mechanism = mechanism
          @jumper = device == 9 ? JUMPER : 0
          mechanism.tia = self
          super()
          @inputs[0] = 0xff
          @inputs[1] = 0xff
          @inputs[2] = 0xff
        end

        def reset!
          super
          mode_written
        end

        def peek(addr)
          mechanism = @mechanism
          mechanism.release_byte_latch
          case addr & 0x07
          when 1 then @inputs[1] = mechanism.latched_byte
          when 2 then @inputs[2] = (@inputs[2] & DAV) | (mechanism.sync? ? 0 : SYNC) | @jumper | 0x1f
          end
          super
        end

        def poke(addr, value)
          @mechanism.release_byte_latch
          super
          register = addr & 0x07
          mode_written if [2, 5].include?(register)
        end

        # What port B drives onto the head's write shift register.
        def port_b_output = output(1)

        private

        # MODE selects reading while high, as the 1541's CB2 does.
        def mode_written
          @mechanism.cb2_written(output(2).anybits?(MODE))
        end
      end
    end
  end
end
