# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module CBM2
        # Acia1 1.1, the 6551: the transmitter's and the receiver's data
        # registers, the status, the command and control registers, the
        # transmitter's state (0 idle, 2 a byte waiting), then four clocks:
        # the cycles to the transmitter's next character end, a clock
        # xcbm2 leaves 0, the cycles to its next receiver poll and another
        # 0.
        #
        # Written: the registers, the status as a read finds it, and while
        # the transmitter is on, the cycles to its character's end in both
        # clocks. Read: the registers, the receiver full, the transmitter
        # empty, the interrupt and the errors from the status, and the
        # transmitter's character end from its clock, or one a character's
        # time on when the clock has run out. Nothing is plugged
        # in, in either, and a character being shifted out is lost.
        module ACIA
          NAME = "Acia1"
          MAJOR = 1
          MINOR = 1
          WAITING = 2
          ERRORS = 0x07
          RECEIVER_FULL = 0x08
          TRANSMITTER_EMPTY = 0x10
          IRQ = 0x80

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          # The module from the ACIA's BL-ACIA fields in `input`, for a
          # machine at `cycles`.
          def export(input, cycles)
            empty = input.bool("transmitter_empty", true)
            status = input.int("errors", 0) | Chips::ACIA::DCD | Chips::ACIA::DSR
            status |= RECEIVER_FULL if input.bool("receiver_full", false)
            status |= TRANSMITTER_EMPTY if empty
            status |= IRQ if input.bool("irq", false)
            at = input.int("transmit_at", Chips::ACIA::NEVER)
            due = at == Chips::ACIA::NEVER ? 0 : [at - cycles, 0].max
            FieldWriter.new.byte(input.int("transmit_data", 0)).byte(input.int("receive_data", 0)).byte(status)
                       .byte(input.int("command", 0)).byte(input.int("control", 0)).byte(empty ? 0 : WAITING)
                       .dword(due).dword(0).dword(due).dword(0).section(NAME, MAJOR, MINOR)
          end

          # The ACIA by its BL-ACIA keys, in a keyed module's writer, for a
          # machine at `cycles`.
          def import(section, out, cycles)
            fields = FieldReader.new(section)
            transmit, receive, status, command, control = fields.bytes(5)
            fields.skip(1)
            due = fields.dword
            out.int("command", command).int("control", control).int("errors", status & ERRORS)
            out.bool("receiver_full", status.anybits?(RECEIVER_FULL))
            out.bool("transmitter_empty", status.anybits?(TRANSMITTER_EMPTY)).bool("irq", status.anybits?(IRQ))
            out.int("receive_data", receive).int("transmit_data", transmit).int("shifting", Chips::ACIA::IDLE)
            out.int("transmit_remainder", 0)
            return out.int("transmit_at", Chips::ACIA::NEVER) unless transmitting?(command)

            out.optional_int("transmit_at", due.positive? ? cycles + due : nil)
          end

          def transmitting?(command)
            control = command & 0x0c
            control != 0 && control != 0x0c
          end
        end
      end
    end
  end
end
