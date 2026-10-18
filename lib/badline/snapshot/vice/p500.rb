# frozen_string_literal: true

require "badline/snapshot/vice/p500_vicii"

module Badline
  module Snapshot
    module Vice
      # xcbm5x0's modules for the P500, the CBM 510: the B series' CPU,
      # CIA, TPIs, ACIA and SID modules (CBM2), CBM2MEM with segment 15's
      # video matrix and colour RAM, xcbm5x0's own VIC-II (VICII) and
      # C500DATA, the cycles to the mains' next tick as a dword, then 4
      # bytes xcbm5x0 leaves 0. They go
      # through the machine's keyed modules as the B series' do, and the
      # VIC through badline's VIC as the C64's does.
      module P500
        # The modules xcbm5x0 resets the machine without, each as xcbm5x0
        # leaves them with nothing attached.
        BEFORE_VIC = [["FSDRIVE", 0, 0, Array.new(258, 0)]].freeze
        AFTER_VIC = [["TAPEPORT", 1, 0, [0x01, 0x01]], ["JOYPORT0", 0, 0, [0x01]], ["JOYSTICK0", 1, 2, [0x00, 0x00]],
                     ["JOYPORT1", 0, 0, [0x01]], ["JOYSTICK1", 1, 2, [0x00, 0x00]]].freeze
        MAINS = "C500DATA"
        # CBM2MEM's second byte, which names the P500.
        P500_RAM = 0x40
        MATRIX = 0x400
        # How many cycles after C500DATA's count badline's mains falls, so
        # that TPI1 latches it on xcbm5x0's cycle.
        TICK_LEAD = 4

        module_function

        def export(machine, sections)
          readers = {}
          sections.each { |section| readers[section.name] = Keyed::Reader.parse(section) }
          machine.sid.catch_up!
          irqs = [machine.tpi1.irq?, machine.vic.interrupted?].count(true)
          [PET::MainCPU.write(machine, irqs), memory(machine), fixed("CBM2CART", 0, 1, [0x00]),
           CIAs.section(machine.cia, "CIA1"),
           *CBM2::TPI::NAMES.map { |name| CBM2::TPI.export(name, CBM2.reader(readers, "BL-#{name}")) },
           CBM2::ACIA.export(CBM2.reader(readers, "BL-ACIA"), machine.cycles),
           SIDRegisters.export(machine), SIDExtended.export(machine), *BEFORE_VIC.map { |entry| fixed(*entry) },
           VICII.export(machine), mains(CBM2.reader(readers, "BL-MACHINE")), *AFTER_VIC.map { |entry| fixed(*entry) }]
        end

        def fixed(name, major, minor, bytes) = FieldWriter.new.bytes(bytes).section(name, major, minor)

        # CBM2MEM as xcbm5x0 writes it: 128K, the P500's byte, the model
        # line, both segment registers, segment 15's RAM with the registers
        # in its first two bytes, the video matrix, the colour RAM a nibble
        # a byte, then segments 0 and 1.
        def memory(machine)
          bus = machine.bus
          system = bus.ram.snapshot
          system[0] = bus.execution_segment
          system[1] = bus.indirect_segment
          fields = FieldWriter.new.byte(1).byte(P500_RAM).byte(CBM2::CBM2Mem::M600_50HZ)
          fields.byte(bus.execution_segment).byte(bus.indirect_segment).bytes(system).bytes(bus.screen.snapshot)
          fields.bytes(Array.new(MATRIX) { |offset| machine.color_ram.nibble(0xd400 + offset) })
          Badline::CBM2::P500::Model::RAM_SEGMENTS.each { |segment| fields.bytes(bus.segment_ram[segment].snapshot) }
          fields.section(CBM2::CBM2Mem::NAME, CBM2::CBM2Mem::MAJOR, CBM2::CBM2Mem::MINOR)
        end

        # C500DATA: the cycles to the mains' next tick, TICK_LEAD less than
        # to the falling edge BL-MACHINE's countdown and level put it at.
        def mains(machine)
          countdown = machine.int("mains_countdown", 1)
          cycles = machine.bool("mains_high", true) ? countdown : countdown + half_period(machine)
          FieldWriter.new.dword([cycles - TICK_LEAD, 0].max).zeros(4).section(MAINS, 0, 0)
        end

        def half_period(machine)
          setup = CBM2Setup.read_fields(machine)
          Badline::CBM2::P500::Model.named(setup.model).region.clock_hz / (2 * setup.mains_hz)
        end

        # The cycles to the mains' falling edge where xcbm5x0 ticks it.
        def cycles_to_tick(section) = FieldReader.new(section).dword + TICK_LEAD

        # How the machine xcbm5x0 saved was built: a 510, NTSC where
        # xcbm5x0's picture has NTSC's lines, at its region's mains.
        def setup(container)
          memory = CBM2.memory(container)
          unless CBM2::CBM2Mem.mapped(memory) == P500_RAM && CBM2::CBM2Mem.ram_kb(memory) == 128
            raise FormatError, "#{memory}: a P500 built otherwise than badline's 510, with 128K of RAM"
          end

          vic = container[VICII::NAME]
          ntsc = !vic.nil? && VICII.reads?(vic) && VICII.picture_lines(vic) == VICII::SIZES.fetch(263).last
          model = ntsc ? "510ntsc" : "510"
          CBM2Setup.new(model:, kernal: Badline::CBM2::P500::Model::KERNALS.keys.first,
                        mains_hz: Badline::CBM2::P500::Model.named(model).region.mains_hz, refresh: false)
        end
      end
    end
  end
end
