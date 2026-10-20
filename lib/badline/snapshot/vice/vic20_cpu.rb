# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module Vic20
        # The 6502 as xvic 3.10 saves it, MAINCPU 1.4, 83 bytes: the clock,
        # the registers, four dwords (the last opcode and three xvic keeps
        # at 0 between instructions), five clocks of the IRQ and NMI
        # bookkeeping, then the IRQ and NMI source counts and the pending
        # interrupts. It is x64sc's MAINCPU 1.4 without the BA flags and
        # the two clocks at its end, and xpet's MAINCPU 1.3 with one more
        # dword. The layout was inferred from xvic's snapshots against its
        # monitor's registers and clock.
        #
        # Written: the clock and the registers, which between instructions
        # are the whole CPU, with VIA 2 counted as an IRQ source while it
        # pulls the line, and VIA 1 as an NMI source. VICE's interrupt
        # clocks are written as long past.
        #
        # Read: the clock and the registers. The CPU starts on an
        # instruction boundary, as xvic's snapshot is taken on one.
        module MainCPU
          NAME = "MAINCPU"
          MAJOR = 1
          MINOR = 4
          SIZE = 83
          IK_IRQ = 0x02

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR && section.data.bytesize == SIZE

          def export(machine)
            cpu = machine.cpu
            fields = FieldWriter.new.qword(machine.cycles)
            [cpu.a, cpu.x, cpu.y, cpu.stack_pointer].each { |register| fields.byte(register) }
            fields.word(cpu.program_counter).byte(cpu.p)
            4.times { fields.dword(0) }
            5.times { fields.qword(0) }
            irqs = machine.via2.irq? ? 1 : 0
            fields.dword(irqs).dword(machine.via1.irq? ? 1 : 0).dword(irqs.positive? ? IK_IRQ : 0)
            fields.section(NAME, MAJOR, MINOR)
          end

          # The clock and the registers by their BL-CPU keys, in a keyed
          # module's writer, and the clock.
          def import(section, out)
            fields = FieldReader.new(section)
            clock = fields.qword
            out.int("a", fields.byte).int("x", fields.byte).int("y", fields.byte).int("sp", fields.byte)
            out.int("pc", fields.word).int("p", fields.byte).int("cycles", clock)
            clock
          end

          def clock(section) = FieldReader.new(section).qword
        end
      end
    end
  end
end
