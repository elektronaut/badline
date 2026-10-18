# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # The 6502 as xpet 3.10 saves it, MAINCPU 1.3: the clock, the
        # registers, the last opcode and two words after it, then the IRQ
        # and NMI bookkeeping: five clocks, the IRQ and NMI source counts and
        # the pending interrupts. xpet's MAINCPU has no BA line to save.
        #
        # Written: the clock and the registers, which between instructions
        # are the whole CPU, with the IRQ sources that pull the line and a
        # pending IRQ. VICE's interrupt clocks are written as long past.
        #
        # Read: the clock and the registers. The CPU starts on an
        # instruction boundary, as xpet's snapshot is taken on one.
        module MainCPU
          NAME = "MAINCPU"
          MAJOR = 1
          MINOR = 3
          IK_IRQ = 0x02

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          def export(machine) = write(machine, [machine.pia1.irq?, machine.pia2.irq?, machine.via.irq?].count(true))

          # The module for `machine`, whose CPU's IRQ line `irqs` sources
          # pull.
          def write(machine, irqs)
            cpu = machine.cpu
            fields = FieldWriter.new.qword(machine.cycles)
            [cpu.a, cpu.x, cpu.y, cpu.stack_pointer].each { |register| fields.byte(register) }
            fields.word(cpu.program_counter).byte(cpu.p)
            fields.dword(0).dword(0).dword(0)
            5.times { fields.qword(0) }
            fields.dword(irqs).dword(0).dword(irqs.positive? ? IK_IRQ : 0)
            fields.section(NAME, MAJOR, MINOR)
          end

          # The clock, the registers by their BL-CPU keys, in a keyed
          # module's writer.
          def import(section, out)
            fields = FieldReader.new(section)
            clock = fields.qword
            out.int("a", fields.byte).int("x", fields.byte).int("y", fields.byte).int("sp", fields.byte)
            out.int("pc", fields.word).int("p", fields.byte).int("cycles", clock)
            clock
          end
        end

        # The SuperPET's 6809, CPU6809 1.1, which xpet saves on every model
        # and won't load a snapshot without: the clock and the registers as
        # an xpet with no SuperPET board leaves them. badline doesn't read
        # it.
        module CPU6809
          NAME = "CPU6809"

          module_function

          def export(machine)
            FieldWriter.new.qword(machine.cycles).zeros(11).byte(0x04).zeros(7).section(NAME, 1, 1)
          end
        end
      end
    end
  end
end
