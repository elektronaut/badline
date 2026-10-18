# frozen_string_literal: true

require "badline/snapshot/vice/cbm2_mem"
require "badline/snapshot/vice/cbm2_tpi"
require "badline/snapshot/vice/cbm2_acia"
require "badline/snapshot/vice/cbm2_crtc"
require "badline/snapshot/vice/cbm2_mains"
require "badline/snapshot/vice/cbm2_restore"

module Badline
  module Snapshot
    module Vice
      # xcbm2's modules for the CBM-II's B series: the CPU, the RAM, the
      # CRTC, the CIA, both TPIs, the ACIA and the SID, written from
      # badline's machine and read into it. Each module's file says what
      # maps and what is approximated. The CPU's, the CIA's and the SID's
      # are the PET's and the C64's. They go through the machine's own
      # keyed fields (Keyed), which a save writes and a load reads, but for
      # the CIA and the SID, which go through the chips as the C64's do.
      module CBM2
        # The models badline builds by the RAM board's size in K and
        # whether the model line is a 700's.
        MODELS = { [128, false] => "610", [256, false] => "620", [128, true] => "710", [256, true] => "720" }.freeze
        # The modules xcbm2 resets the machine without, each as xcbm2 leaves
        # them with nothing attached: no cartridge, no file system drive
        # open, the cassette port on with a datasette in it, and nothing in
        # the user port.
        PERIPHERALS = [["CBM2CART", 0, 1, [0x00]], ["FSDRIVE", 0, 0, Array.new(258, 0)],
                       ["TAPEPORT", 1, 0, [0x01, 0x01]], ["USERPORT", 1, 0, [0x01, 0x00]]].freeze

        module_function

        # The modules xcbm2 3.10 reads, in its order, describing `machine`,
        # which Machine::Settling has brought between instructions, from
        # its keyed modules, `sections`.
        def export(machine, sections)
          readers = {}
          sections.each { |section| readers[section.name] = Keyed::Reader.parse(section) }
          machine.sid.catch_up!
          cart, *rest = PERIPHERALS.map do |name, major, minor, bytes|
            FieldWriter.new.bytes(bytes).section(name, major, minor)
          end
          [PET::MainCPU.write(machine, machine.tpi1.irq? ? 1 : 0), CBM2Mem.export(machine), cart,
           CRTC.export(machine, reader(readers, "BL-CRTC"), reader(readers, "BL-VIDEO")),
           CIAs.section(machine.cia, "CIA1"),
           *TPI::NAMES.map { |name| TPI.export(name, reader(readers, "BL-#{name}")) },
           ACIA.export(reader(readers, "BL-ACIA"), machine.cycles),
           SIDRegisters.export(machine), SIDExtended.export(machine), *drives(machine, readers), *rest]
        end

        # The true drive's modules, as xpet's (PET::Drive2031,
        # PET::Drive8050), or with no true drive, DRIVE8 to DRIVE11 as
        # xcbm2 and xcbm5x0 save no drive.
        def drives(machine, readers)
          return no_drives unless machine.true_drive

          PET::Drive2031.export(machine, readers) + PET::Drive8050.export(machine, readers)
        end

        def no_drives = PET::Drive2031::UNITS.map { |name| PET::Drive2031.unit(PET::Drive2031::NONE, name) }

        def reader(readers, name) = readers[name] || Keyed::Reader.missing(name)

        # How the machine xcbm2 saved was built: the model from the RAM
        # board's size and the model line, and the mains from the model
        # line too, 60 Hz on a 600 whose line says so and 50 Hz otherwise:
        # xcbm2 has no 700 at 60 Hz. xcbm2 doesn't save its ROMs, so the
        # KERNAL is 901244-04a, xcbm2's own.
        def setup(container)
          memory = memory(container)
          ram_kb = CBM2Mem.ram_kb(memory)
          line = CBM2Mem.line(memory)
          unless CBM2Mem.mapped(memory).zero?
            raise FormatError, "#{memory}: RAM in segment 15 beyond the B series', which badline doesn't build"
          end

          model = MODELS[[ram_kb, line == CBM2Mem::M700]]
          raise FormatError, "#{memory}: a CBM-II with #{ram_kb}K of RAM, which badline doesn't build" if model.nil?

          CBM2Setup.new(model:, kernal: "04a", mains_hz: line == CBM2Mem::M600_60HZ ? 60 : 50, refresh: true)
        end

        def memory(container)
          section = container[CBM2Mem::NAME]
          raise FormatError, "the snapshot has no #{CBM2Mem::NAME} module" if section.nil?
          raise FormatError, "#{section}: badline doesn't read this version" unless CBM2Mem.reads?(section)

          section
        end
      end
    end
  end
end
