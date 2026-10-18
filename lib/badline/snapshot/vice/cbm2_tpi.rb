# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module CBM2
        # TPI1 and TPI2 1.0, the 6525s: PRA, PRB, PRC, DDRA, DDRB, DDRC, CR
        # and the AIR, then the interrupts latched and not yet taken through
        # the AIR, and CA in bit 7 and CB in bit 6 of the last byte. In mode
        # 1 xcbm2 keeps the latches in PRC's low five bits and the mask in
        # DDRC's.
        #
        # xcbm2 saves no priority stack: a TPI read from its snapshot has
        # none in service, and one written for it loses the one it has. The
        # levels on the interrupt inputs aren't saved either, so they are
        # read as the machine drives them (CBM2::Restore).
        #
        # Written and read: the registers, the latches, the mask, the AIR,
        # CA and CB.
        module TPI
          NAMES = %w[TPI1 TPI2].freeze
          MAJOR = 1
          MINOR = 0
          LATCHES = 0x1f
          CA = 0x80
          CB = 0x40

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          # The module `name` from the TPI's BL-TPI fields in `input`.
          def export(name, input)
            pra, prb, prc = input.ints("ports", [0, 0, 0])
            ddra, ddrb, ddrc = input.ints("directions", [0, 0, 0])
            control = input.int("control", 0)
            latches = input.int("latches", 0)
            prc = (prc & ~LATCHES) | latches if control.anybits?(0x01)
            lines = (input.bool("ca", false) ? CA : 0) | (input.bool("cb", false) ? CB : 0)
            FieldWriter.new.bytes([pra, prb, prc, ddra, ddrb, ddrc, control, input.int("air", 0), latches, lines])
                       .section(name, MAJOR, MINOR)
          end

          # The registers by their BL-TPI keys, in a keyed module's writer,
          # with `lines` the levels on the interrupt inputs.
          def import(section, out, lines)
            pra, prb, prc, ddra, ddrb, ddrc, control, air, _taken, edges = FieldReader.new(section).bytes(10)
            out.ints("ports", [pra, prb, prc]).ints("directions", [ddra, ddrb, ddrc]).int("control", control)
            mode1 = control.anybits?(0x01)
            out.int("latches", mode1 ? prc & LATCHES : 0)
            out.int("air", mode1 ? air & LATCHES : 0).ints("stack", [])
            out.bool("ca", edges.anybits?(CA)).bool("cb", edges.anybits?(CB)).int("lines", lines)
          end
        end
      end
    end
  end
end
