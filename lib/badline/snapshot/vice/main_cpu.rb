# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # The 6510 as x64sc saves it: MAINCPU 1.4 from VICE 3.8 on, 1.2
      # before, and MAINC64CPU 1.5, the same fields under a new name, in
      # VICE's development versions. The clock, the registers, the last
      # opcode, the ANE and LXA log levels, whether the CPU is jammed and the
      # BA low flags, then the interrupt bookkeeping: the IRQ, NMI and
      # pending-IRQ clocks, the stolen cycles and when they were stolen, the
      # IRQ and NMI source counts, the pending interrupts and the IRQ and NMI
      # delays. 1.2 lacks the log levels and the jammed flag.
      #
      # Written: the registers as they stand, which between instructions is
      # the whole CPU. VICE's interrupt clocks and delays are written as long
      # past, with the IRQ and NMI source counts and a pending NMI.
      #
      # Read: the clock and the registers. The CPU starts on an instruction
      # boundary, as VICE's snapshot is taken on one, and a pending NMI is
      # taken there.
      module MainCPU
        NAME = "MAINCPU"
        TRUNK_NAME = "MAINC64CPU"
        MAJOR = 1
        MINOR = 4
        # The versions read, by name, and whether each has the log levels
        # and the jammed flag.
        VERSIONS = { "MAINCPU 1.2" => false, "MAINCPU 1.4" => true, "MAINC64CPU 1.5" => true }.freeze
        IK_NMI = 0x01
        IK_IRQ = 0x02

        module_function

        def export(computer)
          cpu = computer.cpu
          fields = FieldWriter.new.qword(computer.cycles)
          [cpu.a, cpu.x, cpu.y, cpu.stack_pointer].each { |register| fields.byte(register) }
          fields.word(cpu.program_counter).byte(cpu.p)
          fields.dword(0).dword(0).dword(0).dword(cpu.jammed? ? 1 : 0).dword(0)
          5.times { fields.qword(0) }
          interrupts(computer, fields)
          fields.qword(0).qword(0)
          fields.section(NAME, MAJOR, MINOR)
        end

        def interrupts(computer, fields)
          irqs = [computer.vic.interrupted?, computer.cia1.interrupted?].count(true)
          nmis = computer.cia2.interrupted? ? 1 : 0
          pending = (irqs.positive? ? IK_IRQ : 0) | (computer.cpu.nmi ? IK_NMI : 0)
          fields.dword(irqs).dword(nmis).dword(pending)
        end

        # The module a snapshot has, under either name.
        def find(container) = container[NAME] || container[TRUNK_NAME]

        def reads?(section) = VERSIONS.key?(section.to_s)

        def import(section, computer)
          fields = FieldReader.new(section)
          clock = fields.qword
          cpu = computer.cpu
          cpu.a, cpu.x, cpu.y, cpu.stack_pointer = Array.new(4) { fields.byte }
          cpu.program_counter = fields.word
          cpu.p = fields.byte
          fields.skip(VERSIONS.fetch(section.to_s) ? 20 : 8)
          fields.skip(40 + 8)
          pending = fields.dword
          cpu.resume(clock)
          cpu.nmi = pending.anybits?(IK_NMI)
          computer.resume_at(clock)
        end
      end
    end
  end
end
