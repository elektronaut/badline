# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # A true 2031 on device 8, as xpet 3.10 saves it with true drive
        # emulation: DRIVE8 to DRIVE11 2.0, one a unit, DRIVECPU0 1.3, the
        # drive's 6502 and its RAM, and its VIAs as VIA 2.2 modules,
        # 2031VIA1D0 at $1800 on the IEEE-488 bus and VIA2D0 at $1C00 on
        # the mechanism.
        #
        # DRIVECPU0 holds the clock, the registers, the last opcode, the
        # main CPU's clock, more clocks of the drive's interrupt bookkeeping,
        # then the 2K of RAM from $5C and twelve bytes after it. DRIVE8
        # holds the head's half track at $10, with track 18 at 36 as badline
        # numbers them, the speed zone its VIA set at $24, $47 and $4B, the
        # drive's type as a word at $28, and from $2C the disk's place in
        # its turn and the clock it was last moved on at. The rest of it,
        # the read electronics among it, badline doesn't read. xpet's head
        # rests on a half track two phases on from where badline's stepper
        # puts it (SLIP).
        #
        # Written: the registers and the RAM, the VIAs as the PET's VIA is
        # written with the stepper's phase moved to xpet's, and DRIVE8 as
        # xpet saves an idle 2031 but for the head's half track, the zone,
        # and the disk at the start of its turn as of the snapshot's clock.
        # The interrupt clocks are written as long past. The snapshot is
        # settled with the drive's CPU between instructions too
        # (PET#settle_for_vice!). One taken while the drive is mid-transfer
        # on the bus may stall there in xpet, as xpet's own snapshots taken
        # while it searches for a file do.
        #
        # Read: the registers, the RAM, the VIAs as the PET's VIA is read,
        # and the head's half track, with the motor, the LED and the zone
        # from VIA 2's port B and the stepper's phase as xpet's (SLIP). The
        # disk turns on from where badline's left it, and the disk in the
        # drive stays.
        module Drive2031
          UNITS = %w[DRIVE8 DRIVE9 DRIVE10 DRIVE11].freeze
          DRIVE_MAJOR = 2
          DRIVE_MINOR = 0
          CPU = "DRIVECPU0"
          CPU_MAJOR = 1
          CPU_MINOR = 3
          VIA1 = "2031VIA1D0"
          VIA2 = "VIA2D0"
          NAMES = [*UNITS, CPU, VIA1, VIA2].freeze
          # Where DRIVECPU0's RAM starts, and its length.
          RAM_AT = 0x5c
          RAM_SIZE = 0x800
          TAIL = 12
          HALF_TRACK = 0x10
          ZONES = [0x24, 0x47, 0x4b].freeze
          SIZE = 145
          # The disk's place in its turn, and the clock it was last moved on at.
          TURN = 0x2c
          # DRIVE8 as xpet saves an idle 2031, and a unit with no drive, by
          # the bytes that aren't 0.
          IDLE = { 0x00 => 0x01, 0x01 => 0x01, 0x02 => 0x01, 0x0f => 0x01, 0x10 => 0x25, 0x1a => 0x01, 0x1b => 0xdf,
                   0x1f => 0x54, 0x20 => 0x55, 0x24 => 0x03, 0x28 => 0xef, 0x29 => 0x07, 0x2c => 0x60, 0x2d => 0x41,
                   0x2e => 0x0f, 0x30 => 0x17, 0x31 => 0x51, 0x32 => 0x0f, 0x40 => 0x54, 0x41 => 0x01, 0x42 => 0x54,
                   0x47 => 0x03, 0x4b => 0x03, 0x6f => 0xcd, 0x70 => 0xab, 0x71 => 0x34, 0x72 => 0x12 }.freeze
          NONE = { 0x00 => 0x01, 0x01 => 0x01, 0x02 => 0x01, 0x0e => 0x01, 0x0f => 0x01, 0x10 => 0x24, 0x1a => 0x01,
                   0x20 => 0x55, 0x6f => 0xcd, 0x70 => 0xab, 0x71 => 0x34, 0x72 => 0x12, 0x8f => 0x01 }.freeze
          SLIP = 2
          MOTOR = 0x04
          LED = 0x08

          module_function

          # Whether the snapshot has a true 2031.
          def present?(container) = !container[CPU].nil? && !container[VIA1].nil?

          def reads?(section)
            case section.name
            when CPU then section.major == CPU_MAJOR && section.minor == CPU_MINOR
            when VIA1, VIA2 then VIA.reads?(section)
            else section.major == DRIVE_MAJOR && section.minor == DRIVE_MINOR
            end
          end

          # xpet's modules for the 2031 whose BL-D8 modules `readers` holds,
          # and none without one or for an 8050 or 8250, which they leave
          # out.
          def export(machine, readers)
            drive = readers["BL-D8"]
            return [] if drive.nil? || drive.text("model", "2031") != "2031"

            via2 = readers.fetch("BL-D8-VIA2")
            mechanism = readers.fetch("BL-D8-MECH")
            zone = ((via2.int("orb", 0) | ~via2.int("ddrb", 0)) >> 5) & 0x03
            idle = filled(IDLE)
            idle[HALF_TRACK] = mechanism.int("half_track", 36)
            ZONES.each { |offset| idle[offset] = zone }
            idle[TURN, 8] = [0, machine.cycles & 0xffff_ffff].pack("VV").bytes
            [FieldWriter.new.bytes(idle).section(UNITS.first, DRIVE_MAJOR, DRIVE_MINOR),
             *UNITS.drop(1).map { |name| unit(NONE, name) },
             cpu(machine, readers.fetch("BL-D8-CPU"), readers.fetch("BL-D8-RAM")),
             stepper(VIA.export(via2, VIA2), mechanism.int("slip", 0)),
             VIA.export(readers.fetch("BL-D8-VIA1"), VIA1)]
          end

          # VIA 2's port B with the stepper's phase as xpet's head takes it
          # where badline's head is: SLIP on from badline's.
          def stepper(section, slip)
            bytes = section.data.bytes
            bytes[2] = (bytes[2] & 0xfc) | ((bytes[2] - slip + SLIP) & 0x03)
            section.with(data: bytes.pack("C*"))
          end

          def unit(bytes, name) = FieldWriter.new.bytes(filled(bytes)).section(name, DRIVE_MAJOR, DRIVE_MINOR)

          def filled(bytes) = Array.new(SIZE) { |offset| bytes.fetch(offset, 0) }

          def cpu(machine, input, ram)
            fields = FieldWriter.new.qword(machine.cycles)
            %w[a x y sp].each { |key| fields.byte(input.int(key, 0)) }
            fields.word(input.int("pc", 0)).byte(input.int("p", 0x20)).dword(0)
            fields.qword(machine.cycles).zeros(16).qword(machine.cycles).zeros(1).qword(0).zeros(8).qword(0)
            fields.zeros(16)
            bytes = ram.bytes("ram", "".b).bytes
            fields.bytes(Array.new(RAM_SIZE) { |address| bytes[address] || 0 }).zeros(TAIL)
            fields.section(CPU, CPU_MAJOR, CPU_MINOR)
          end

          # The 2031's keyed modules, named for device 8, from the
          # snapshot's, with `disk` the drive's disk module badline keeps,
          # or nil.
          def import(container, disk)
            via2 = container[VIA2]
            sections = [Keyed.section("BL-D8") { |out| drive(container, out) },
                        Keyed.section("BL-D8-RAM") { |out| out.bytes("ram", ram(container[CPU])) },
                        Keyed.section("BL-D8-VIA1") { |out| VIA.import(container[VIA1], out) },
                        Keyed.section("BL-D8-VIA2") { |out| VIA.import(via2, out) },
                        Keyed.section("BL-D8-CPU") { |out| registers(container[CPU], out) },
                        Keyed.section("BL-D8-MECH") { |out| mechanism(container, via2, out) }]
            disk ? sections + [disk] : sections
          end

          def drive(container, out)
            out.text("model", "2031").int("phase", 0).int("cycles", FieldReader.new(container[CPU]).qword)
            out.bool("so_pending", false)
          end

          def ram(section) = FieldReader.new(section).skip(RAM_AT).string(RAM_SIZE)

          def registers(section, out)
            fields = FieldReader.new(section)
            clock = fields.qword
            out.int("a", fields.byte).int("x", fields.byte).int("y", fields.byte).int("sp", fields.byte)
            out.int("pc", fields.word).int("p", fields.byte).int("cycles", clock)
          end

          # The head where DRIVE8 has it, and the stepper's phase as VIA 2
          # drives it, which the half track's low two bits stand for.
          def mechanism(container, via2, out)
            half_track = FieldReader.new(container[UNITS.first]).skip(HALF_TRACK).byte
            bytes = FieldReader.new(via2).bytes(4)
            port_b = bytes[2] | (~bytes[3] & 0xff)
            out.int("half_track", half_track).int("slip", SLIP)
            out.int("zone", (port_b >> 5) & 0x03)
            out.bool("motor", port_b.anybits?(MOTOR)).bool("led", port_b.anybits?(LED))
          end
        end
      end
    end
  end
end
