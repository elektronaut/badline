# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # The SuperPET's 6702 in PETMEM's settings at the end, from their
        # fifth byte: the byte the 6702 reads, the last write that shifted
        # it, 1 while the last write left D0 clear, then a little-endian word
        # for each data line's shift register. Bit k of a word, below the
        # register's last stage, is stage k XORed with stage k + 1, and its
        # last stage's bit is that stage XORed with the stage the next shift
        # brings in if the latch then holds the last write that shifted.
        # Every PET's settings hold a 6702 as the RES line leaves it.
        #
        # Mapped from xpet 3.10's snapshots after each of 56 writes to $EFE0
        # from its monitor, against PET::SuperPET::Dongle after the same
        # writes.
        #
        # Written and read: the registers, and whether D0 was clear in the
        # last write. A write the 6702 hasn't shifted on yet is written as
        # shifted. Read, the latch is $00 or $FF by D0, and no shift waits.
        module Dongle
          # Offsets in PETMEM's settings.
          AT = 4
          LENGTH = 19
          OUTPUT = 0
          ARMED = 2
          WORDS = 3
          # The last write that shifted, as xpet has it after RES.
          RESET_LAST = 0x01

          module_function

          # The settings' bytes for a 6702 with `registers`, after a write
          # of `latch`.
          def export(registers, latch)
            dongle = Badline::PET::SuperPET::Dongle
            incoming = RESET_LAST ^ dongle::FEEDBACK ^ 0xff
            output = 0
            words = []
            8.times do |bit|
              register = registers[bit]
              output |= (register & 1) << bit
              top = dongle::LENGTHS[bit] - 1
              last = ((register >> top) ^ register ^ (incoming >> bit)) & 1
              word = ((register ^ (register >> 1)) & ((1 << top) - 1)) | (last << top)
              words << (word & 0xff) << (word >> 8)
            end
            [output ^ dongle::INVERTED, RESET_LAST, latch.nobits?(0x01) ? 1 : 0, *words]
          end

          # The 6702's BL-SUPERPET keys from the settings' `bytes`, in a keyed
          # module's writer.
          def import(bytes, out)
            dongle = Badline::PET::SuperPET::Dongle
            stages = bytes[OUTPUT] ^ dongle::INVERTED
            registers = Array.new(8) do |bit|
              word = bytes[WORDS + (bit * 2)] | (bytes[WORDS + (bit * 2) + 1] << 8)
              stage = (stages >> bit) & 1
              register = stage
              (dongle::LENGTHS[bit] - 1).times do |index|
                stage ^= (word >> index) & 1
                register |= stage << (index + 1)
              end
              register
            end
            out.ints("dongle.registers", registers).int("dongle.latch", bytes[ARMED].zero? ? 0xff : 0x00)
          end
        end
      end
    end
  end
end
