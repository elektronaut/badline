# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module CBM2
        # CBM2MEM 1.0: the RAM board's size in units of 128K, the RAM xcbm2
        # maps into segment 15 beyond the B series' own (none on a B series
        # as built, $40 on a P500), its model line (0 a 700, 1 a 600 at
        # 60 Hz, 2 a 600 at 50 Hz), the execution and indirection segment
        # registers, then segment 15's 2K of RAM, the 2K of screen RAM, and
        # the board's segments from segment 1 up.
        #
        # xcbm2 keeps the segment registers in segment 15's bytes $0000 and
        # $0001 too, and they are written there. Under the registers
        # badline's RAM is never written, so those two bytes read as 0.
        # xcbm2's ROMs aren't in the snapshot.
        module CBM2Mem
          NAME = "CBM2MEM"
          MAJOR = 1
          MINOR = 0
          SEGMENT = 0x10000
          SYSTEM_RAM = 0x800
          SCREEN_RAM = 0x800
          HEADER = 5
          # The model lines.
          M700 = 0
          M600_60HZ = 1
          M600_50HZ = 2

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          def model_line(machine)
            return M700 if machine.model.high_profile

            machine.mains_hz == 60 ? M600_60HZ : M600_50HZ
          end

          def export(machine)
            bus = machine.bus
            system = bus.ram.snapshot
            system[0] = bus.execution_segment
            system[1] = bus.indirect_segment
            fields = FieldWriter.new.byte(machine.model.ram_segments.length / 2).byte(0).byte(model_line(machine))
            fields.byte(bus.execution_segment).byte(bus.indirect_segment)
            fields.bytes(system).bytes(bus.screen.snapshot)
            machine.model.ram_segments.each { |segment| fields.bytes(bus.segment_ram[segment].snapshot) }
            fields.section(NAME, MAJOR, MINOR)
          end

          # The RAM in K, the RAM mapped into segment 15 and the model line.
          def ram_kb(section) = FieldReader.new(section).byte * 128

          def mapped(section) = FieldReader.new(section).skip(1).byte

          def line(section) = FieldReader.new(section).skip(2).byte

          # The RAM and the segment registers by their BL-RAM keys, in a
          # keyed module's writer, for a machine whose board fills
          # `segments`.
          def import(section, out, segments)
            fields = FieldReader.new(section).skip(3)
            out.int("execution_segment", fields.byte & 0x0f).int("indirect_segment", fields.byte & 0x0f)
            system = fields.string(SYSTEM_RAM)
            out.bytes("system", "\0\0".b + system.byteslice(2, SYSTEM_RAM - 2))
            out.bytes("screen", fields.string(SCREEN_RAM))
            segments.each { |segment| out.bytes("segment#{segment}", fields.string(SEGMENT)) }
          end
        end
      end
    end
  end
end
