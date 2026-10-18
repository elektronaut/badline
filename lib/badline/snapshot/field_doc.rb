# frozen_string_literal: true

require "badline"
require "badline/c128"
require "badline/plus4"

module Badline
  module Snapshot
    # doc/snapshot-format.md, written by running the code: each family's
    # machine is saved with its attachments, and its modules loaded into a
    # machine built the same way at power-on through Keyed::Recorders,
    # which note every key read with its type and the value the new machine
    # had, its default. `rake snapshot:fields` writes it, and a spec checks
    # that the file matches.
    module FieldDoc
      PATH = File.expand_path("../../../doc/snapshot-format.md", __dir__)

      # Modules read through Recorders.
      class RecordingModules < Keyed::Modules
        private

        def parse(section) = Keyed::Recorder.parse(section)

        def missing(name) = Keyed::Recorder.missing(name)
      end

      # One machine saved and loaded: the family it belongs to, and for
      # each module the keys its records hold, with their tags, and the fields the load read.
      Load = Data.define(:family, :written, :fields)

      # The cartridges by CRT hardware type: EasyFlash, then a mapper of
      # each kind of register: Ocean's bank, Comal-80's bank for both
      # windows, Zaxxon's ROMH bank, and the Action Replay's and the
      # Pagefox's control registers.
      CARTRIDGES = [32, 5, 21, 18, 1, 53].freeze

      # The machines the doc is made from: each family at power-on, the C64
      # with each kind of expansion, cartridge and media, and a second SID,
      # the 264 series' models, its TCBM interface, cartridge, tape and
      # true drives, the 1541 and the 1551, a CRTC PET, a 2001, an 8096,
      # an 8296 with its user port jumpered, a PET with a disk and tapes and
      # one with a true 2031, and a 610, a 720 and a 610 with a cartridge.
      def self.machines
        {
          "c64" => [C64.new, C64.new(ram_expansion: :plus256k), C64.new(reu: 512),
                    *CARTRIDGES.map { |type| with_cartridge(type) }, with_trap_dos, with_tape, with_drive(:d64),
                    with_drive(:d81), with_extra_sids],
          "vic20" => [Vic20.new, with_rom],
          "c128" => [C128.new(mode: :c128), with_drive(:d71)],
          "plus4" => [Plus4.new, Plus4.new(model: "c16"), Plus4.new(tcbm: true), Plus4.new(sid_card: :mos6581),
                      Plus4.new(sid_card: :mos8580, sid_card_address: 0xfe80),
                      Plus4.new(ram_expansion: :csory256),
                      plus4_with_cartridge, plus4_with_tape, plus4_with_drive, plus4_with_drive("1551")],
          "pet" => [PET.new, PET.new(model: "2001"), PET.new(model: "8096"),
                    PET.new(model: "8296", characters: "din", jumpers: %w[userport]), pet_with_media,
                    pet_with_drive],
          "cbm2" => [CBM2.new, CBM2.new(model: "720", kernal: "03b", mains_hz: 60), cbm2_with_cartridge]
        }
      end

      # A PET with a disk in device 8 through the traps and a tape in each
      # datasette.
      def self.pet_with_media
        bytes = "C64-TAPE-RAW".bytes + [1, 3, 0, 0, 4, 0, 0, 0, 0x30, 0x30, 0x30, 0x30]
        PET.new.tap do |machine|
          machine.mount(Storage::D64Image.new("", read_only: true, bytes: blank(174_848)))
          machine.cassettes.datasette1.insert(Storage::TAP.new("", bytes:))
          machine.cassettes.datasette2.insert(Storage::TAP.new("", bytes:))
        end
      end

      # A PET with a 2031 holding a blank disk.
      def self.pet_with_drive
        PET.new.tap do |machine|
          image = Storage::D64Image.new("", bytes: blank(174_848))
          machine.plug_true_drive.insert(Drives::Model1541::Disk.decode(image))
        end
      end

      def self.blank(length) = Array.new(length, 0)

      # A 610 with an 8K cartridge ROM at $2000.
      def self.cbm2_with_cartridge
        chip = Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0x2000, data: blank(0x2000))
        CBM2.new.tap { |machine| machine.attach_cartridge([chip]) }
      end

      def self.with_cartridge(type)
        chips = [0x8000, 0xa000].map do |address|
          Storage::CRTFile::Chip.new(chip_type: 2, bank: 0, address:, data: blank(0x2000))
        end
        image = Storage::CRTFile::Image.new(hardware_type: type, subtype: 0, exrom: 1, game: 0, name: "DOC", chips:)
        C64.new.tap do |machine|
          machine.attach_cartridge(C64::Cartridge.from_crt(Storage::CRTFile.new(bytes: Storage::CRTFile.encode(image))))
        end
      end

      # The SID player's machine for a tune on two SIDs.
      def self.with_extra_sids
        C64.new.tap { |machine| machine.address_bus.add_sid(Chips::SID.new(at: 0xd420)) }
      end

      def self.with_trap_dos
        C64.new.tap { |machine| machine.mount(Storage::D64Image.new("", read_only: true, bytes: blank(174_848))) }
      end

      def self.with_tape
        bytes = "C64-TAPE-RAW".bytes + [1, 0, 0, 0, 4, 0, 0, 0, 0x30, 0x30, 0x30, 0x30]
        C64.new.tap { |machine| machine.datasette.insert(Storage::TAP.new("", bytes:)) }
      end

      def self.with_drive(kind)
        case kind
        when :d81
          C64.new.tap do |machine|
            machine.plug_drive1581.insert(Drives::Model1581::Disk.new(Storage::D81Image.new("", bytes: blank(819_200))))
          end
        when :d71
          C128.new(mode: :c128).tap do |machine|
            image = Storage::D71Image.new("", bytes: blank(349_696))
            machine.plug_true_drive.insert(Drives::Model1541::Disk.decode(image))
          end
        else
          C64.new.tap do |machine|
            image = Storage::D64Image.new("", bytes: blank(174_848))
            machine.plug_true_drive.insert(Drives::Model1541::Disk.decode(image))
          end
        end
      end

      # A Plus/4 with a cartridge in each of cartridge 1's slots.
      def self.plus4_with_cartridge
        chips = [0x8000, 0xc000].map do |address|
          Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address:, data: blank(0x4000))
        end
        Plus4.new.tap { |machine| machine.attach_cartridge(chips) }
      end

      # A C16 with a version 2 tape in its datasette, which times the read
      # line's level.
      def self.plus4_with_tape
        bytes = "C16-TAPE-RAW".bytes + [2, 2, 0, 0, 4, 0, 0, 0, 0x30, 0x30, 0x30, 0x30]
        Plus4.new(model: "c16").tap { |machine| machine.datasette.insert(Storage::TAP.new("", bytes:)) }
      end

      def self.plus4_with_drive(model = "1541")
        Plus4.new(true_drive_model: model).tap do |machine|
          image = Storage::D64Image.new("", bytes: blank(174_848))
          machine.plug_true_drive.insert(Drives::Model1541::Disk.decode(image))
        end
      end

      def self.with_rom
        Vic20.new.tap { |machine| machine.bus.map_rom(0xa000, blank(0x2000)) }
      end

      # Saves `machine` and loads it into a new one through Recorders.
      def self.load(family, machine)
        modules = RecordingModules.new(Image.of(machine).sections)
        Image.setup(modules.machine).build.load_modules(modules)
        modules.machine.text("written_by", "")
        written = {}
        fields = {}
        modules.readers.each do |reader|
          written[reader.name] = reader.tags
          fields[reader.name] = reader.fields
        end
        Load.new(family:, written:, fields:)
      end

      def self.loads = machines.flat_map { |family, list| list.map { |machine| load(family, machine) } }

      # The doc, as markdown.
      def self.markdown(loads = self.loads) = Markdown.new(loads).to_s

      def self.write(path = PATH) = File.write(path, markdown)
    end
  end
end

require "badline/snapshot/field_doc/markdown"
