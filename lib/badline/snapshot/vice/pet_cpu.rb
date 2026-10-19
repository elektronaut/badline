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

          def export(machine)
            sources = [machine.pia1.irq?, machine.pia2.irq?, machine.via.irq?]
            sources << machine.acia_irq? if machine.superpet?
            write(machine, sources.count(true))
          end

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
        # and won't load a snapshot without: the clock, X, Y, U, S and PC,
        # DP, CC, A and B, then five bytes. xpet 3.10's layout was inferred
        # from its snapshots of a 6809 running a loop that loads each
        # register with a value of its own; the five bytes are 0 in every
        # snapshot xpet wrote.
        #
        # Written: the clock and the registers, the SuperPET's 6809's
        # between instructions while it has the bus, and otherwise the
        # registers of a 6809 that hasn't run, as xpet leaves them. Read:
        # the registers, with the 6809 on an instruction boundary, as
        # xpet's snapshot is taken on one.
        module CPU6809
          NAME = "CPU6809"
          MAJOR = 1
          MINOR = 1
          # The CC an xpet without a SuperPET board saves.
          IDLE_CC = 0x04

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          def export(machine)
            fields = FieldWriter.new.qword(machine.cycles)
            unless machine.superpet? && machine.m6809_running?
              return fields.zeros(11).byte(IDLE_CC).zeros(7).section(NAME, MAJOR, MINOR)
            end

            cpu = machine.m6809
            [cpu.x, cpu.y, cpu.u, cpu.s, cpu.pc].each { |register| fields.word(register) }
            fields.byte(cpu.dp).byte(cpu.cc).byte(cpu.a).byte(cpu.b).zeros(5).section(NAME, MAJOR, MINOR)
          end

          # The registers by their BL-M6809 keys, in a keyed module's writer,
          # with the 6809's cycle count the machine's `cycles`.
          def import(section, out, cycles)
            fields = FieldReader.new(section).skip(8)
            %w[x y u s pc].each { |name| out.int(name, fields.word) }
            %w[dp cc a b].each { |name| out.int(name, fields.byte) }
            out.int("cycles", cycles).bool("nmi.armed", true)
          end
        end
      end
    end
  end
end
