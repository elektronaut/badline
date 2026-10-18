# frozen_string_literal: true

require "badline/snapshot/vice/pet_cpu"
require "badline/snapshot/vice/pet_mem"
require "badline/snapshot/vice/pet_pias"
require "badline/snapshot/vice/pet_via"
require "badline/snapshot/vice/pet_crtc"
require "badline/snapshot/vice/pet_drive"
require "badline/snapshot/vice/pet_drive8050"
require "badline/snapshot/vice/pet_restore"

module Badline
  module Snapshot
    module Vice
      # xpet's modules for the PET: the CPU, the RAM, the CRTC, both PIAs,
      # the VIA and a true 2031, written from badline's machine and read
      # into it. Each
      # module's file says what maps and what is approximated. They go
      # through the PET's own keyed fields (Keyed), which a save writes and a
      # load reads, so they read no chip's insides.
      module PET
        # The models badline builds by the board PETMEM names (PETMem): the
        # discrete board is a 2001's where xpet's settings say so, and a
        # 3032 otherwise.
        MODELS = { PETMem::CRTC40 => "4032", PETMem::CRTC80 => "8032", PETMem::CBM8096 => "8096",
                   PETMem::CBM8296 => "8296" }.freeze
        # The modules xpet resets the machine without, for the parts badline
        # doesn't model in VICE's terms, each as xpet leaves them with
        # nothing attached: no file system drive open, both cassette ports
        # on with a datasette in #1, and nothing in the user port.
        PERIPHERALS = [
          ["FSDRIVE", 0, 0, Array.new(258, 0)], ["TAPEPORT", 1, 0, [0x01, 0x01, 0x01]], ["USERPORT", 1, 0, [0x01, 0x00]]
        ].freeze
        # The cycles a frame below which a CRTC editor runs at 60 Hz.
        SIXTY_HZ_FRAME = 18_333
        # The 8032's 50 Hz editors by the cycles a line they set up: xpet's
        # own, 901474-04 dated 0283, sets 64.
        EDITOR_0283_LINE = 64

        module_function

        # The modules xpet 3.10 needs, in its order, describing `machine`,
        # which Machine::Settling has brought between instructions, from
        # its keyed modules, `sections`.
        def export(machine, sections)
          readers = {}
          sections.each { |section| readers[section.name] = Keyed::Reader.parse(section) }
          [MainCPU.export(machine), CPU6809.export(machine), PETMem.export(machine),
           CRTC.export(machine, reader(readers, "BL-CRTC"), reader(readers, "BL-VIDEO")),
           PIAs.export("PIA1", machine.pia1, reader(readers, "BL-PIA1")),
           PIAs.export("PIA2", machine.pia2, reader(readers, "BL-PIA2")), VIA.export(reader(readers, "BL-VIA")),
           *Drive2031.export(machine, readers), *Drive8050.export(machine, readers)] +
            PERIPHERALS.map { |name, major, minor, bytes| FieldWriter.new.bytes(bytes).section(name, major, minor) }
        end

        def reader(readers, name) = readers[name] || Keyed::Reader.missing(name)

        # How the machine xpet saved was built: the model from PETMEM's
        # board, the RAM, and on a CRTC board the editor's frame rate, and
        # for an 8032's 50 Hz editor which one, from the CRTC's registers.
        # xpet doesn't save the keyboard, the ROMs or an 8296's jumpers, so
        # a discrete board is a 3032 with the graphics keyboard unless it is
        # a 2001, each model has its own ROMs, and an 8296 none of its
        # jumpers, as xpet's own has.
        def setup(container)
          memory = memory(container)
          ram_kb = PETMem.ram_kb(memory)
          name = model_name(memory)
          profile = Badline::PET::Model.named(name)
          unless Badline::PET::Model.ram_fits?(profile, ram_kb)
            raise FormatError, "#{memory}: a #{name} with #{ram_kb}K of RAM, which badline doesn't build"
          end

          crtc = container[CRTC::NAME]
          crtc = nil unless crtc.nil? || CRTC.reads?(crtc)
          refresh_hz = refresh_hz(crtc, profile)
          profile = Badline::PET::Model.upgraded(profile, nil, editor(crtc, profile, refresh_hz))
          PETSetup.new(model: name, ram_kb:, refresh_hz:, basic: profile.basic, editor: profile.editor(refresh_hz),
                       kernal: profile.kernal, characters: profile.characters, jumpers: "")
        end

        def memory(container)
          section = container[PETMem::NAME]
          raise FormatError, "the snapshot has no #{PETMem::NAME} module" if section.nil?
          raise FormatError, "#{section}: badline doesn't read this version" unless PETMem.reads?(section)

          section
        end

        def model_name(memory)
          board = PETMem.board_of(memory)
          return PETMem.pet2001?(memory) ? "2001" : "3032" if board == PETMem::DISCRETE

          name = MODELS[board]
          return name unless name.nil?

          what = board == PETMem::SUPERPET ? "a SuperPET" : "board #{board}"
          raise FormatError, "#{memory}: #{what}, which badline doesn't build"
        end

        # The editor's frame rate, from the cycles the CRTC's registers set
        # up a frame.
        def refresh_hz(crtc, profile)
          return 60 unless profile.crtc?
          return 50 if crtc.nil?

          registers = CRTC.registers(crtc)
          (registers[0] + 1) * CRTC.frame_lines(registers) > SIXTY_HZ_FRAME ? 50 : 60
        end

        # The editor by ROMSets' name where the model's own doesn't set up
        # the CRTC's frame, or nil.
        def editor(crtc, profile, refresh_hz)
          return nil if crtc.nil? || refresh_hz != 50 || profile.video != :crtc80

          CRTC.registers(crtc)[0] + 1 == EDITOR_0283_LINE ? "4-80-b-50hz-0283" : nil
        end
      end
    end
  end
end
