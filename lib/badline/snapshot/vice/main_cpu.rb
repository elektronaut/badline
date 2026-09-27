# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # MAINCPU 1.2, as x64sc writes it: the clock, the registers, then the
      # interrupt bookkeeping of VICE's CPU core.
      #
      # Written: the registers as they stand, which between instructions is
      # the whole CPU. Mid-instruction, VICE would carry on from the program
      # counter as it stands. VICE's interrupt clocks and delays are written
      # as long past, with the IRQ and NMI lines and a pending NMI.
      #
      # Read: the clock and the registers. The CPU starts on an instruction
      # boundary, as VICE's snapshot is taken on one, and a pending NMI is
      # taken at it.
      module MainCPU
        NAME = "MAINCPU"
        MAJOR = 1
        MINOR = 2
        IK_NMI = 0x01
        IK_IRQ = 0x02

        module_function

        def export(computer)
          cpu = computer.cpu
          fields = FieldWriter.new.qword(computer.cycles)
          [cpu.a, cpu.x, cpu.y, cpu.stack_pointer].each { |register| fields.byte(register) }
          fields.word(cpu.program_counter).byte(cpu.p)
          fields.dword(0).dword(0) # last opcode info, BA low flags
          5.times { fields.qword(0) } # IRQ, NMI and pending clocks, stolen cycles
          interrupts(computer, fields)
          fields.qword(0).qword(0) # IRQ and NMI delay cycles
          fields.section(NAME, MAJOR, MINOR)
        end

        def interrupts(computer, fields)
          irqs = [computer.vic.interrupted?, computer.cia1.interrupted?].count(true)
          nmis = computer.cia2.interrupted? ? 1 : 0
          pending = (irqs.positive? ? IK_IRQ : 0) | (computer.cpu.nmi ? IK_NMI : 0)
          fields.dword(irqs).dword(nmis).dword(pending)
        end

        def import(section, computer)
          fields = FieldReader.new(section)
          clock = fields.qword
          cpu = computer.cpu
          cpu.a, cpu.x, cpu.y, cpu.stack_pointer = Array.new(4) { fields.byte }
          cpu.program_counter = fields.word
          cpu.p = fields.byte
          fields.skip(8 + 40 + 8)
          cpu.nmi = fields.dword.anybits?(IK_NMI)
          computer.instance_variable_set(:@cycles, clock)
          cpu.instance_variable_set(:@cycles, clock)
        end
      end
    end
  end
end
