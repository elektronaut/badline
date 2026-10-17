# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # PIA1 and PIA2 1.0: port A's output and direction registers and
        # its control register as read, with the CA1 and CA2 flags in bits 7
        # and 6, the same for port B, and the levels on CA2 and CB2 in bits
        # 7 and 6 of the last byte, high while a line is an input.
        #
        # Read: each side's flags come from its control register, and a
        # handshake under way from the level its C2 output is at. The levels
        # outside on CA1 and CB1 aren't saved: they stay as the machine has
        # them, with PIA 1's CB1 on the vertical drive line.
        module PIAs
          NAMES = %w[PIA1 PIA2].freeze
          MAJOR = 1
          MINOR = 0
          CA2_HIGH = 0x80
          CB2_HIGH = 0x40
          HANDSHAKE = 0x20

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          # The PIA's module, from its BL-PIA1 or BL-PIA2 fields in `input`.
          def export(name, pia, input)
            fields = FieldWriter.new.byte(input.int("ora", 0)).byte(input.int("ddra", 0)).byte(pia.cra)
            fields.byte(input.int("orb", 0)).byte(input.int("ddrb", 0)).byte(pia.crb)
            fields.byte((pia.ca2_output ? CA2_HIGH : 0) | (pia.cb2_output ? CB2_HIGH : 0))
            fields.section(name, MAJOR, MINOR)
          end

          # The registers and the control lines by their BL-PIA keys, in a
          # keyed module's writer.
          def import(section, out)
            ora, ddra, cra, orb, ddrb, crb, lines = FieldReader.new(section).bytes(7)
            out.int("ora", ora).int("ddra", ddra).int("orb", orb).int("ddrb", ddrb)
            control_lines(out, "ca.", cra, lines.anybits?(CA2_HIGH))
            control_lines(out, "cb.", crb, lines.anybits?(CB2_HIGH))
          end

          def control_lines(out, prefix, register, c2_high)
            control = register & 0x3f
            out.int("#{prefix}control", control).bool("#{prefix}c1_flag", register.anybits?(0x80))
            out.bool("#{prefix}c2_flag", register.anybits?(0x40)).int("#{prefix}pulse", 0)
            out.bool("#{prefix}handshake_low", control & 0x38 == HANDSHAKE && !c2_high)
            out.bool("#{prefix}c2_high", c2_high) if control.nobits?(0x20)
          end
        end
      end
    end
  end
end
