# frozen_string_literal: true

module Badline
  # = Model
  #
  # The C64s badline builds by name, as `--model` selects them: the chips
  # each was sold with, its video standard, its KERNAL and whether it has
  # a datasette. The names are x64sc's.
  module Model
    # Each field but the name is a keyword Computer.new takes.
    Profile = Data.define(:name, :vic_model, :cia_model, :sid_model, :region, :kernal, :datasette, :board)

    # The breadbin PAL C64: the 6569 VIC-II, 6526 CIAs and the 6581 SID.
    C64 = Profile.new(name: "c64", vic_model: :mos6569, cia_model: :mos6526, sid_model: :mos6581,
                      region: Region::PAL, kernal: :c64, datasette: true, board: :c64)

    # The PAL C64C: the HMOS 8565 VIC-II, 6526A CIAs and the 8580 SID.
    C64C = Profile.new(name: "c64c", vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580,
                       region: Region::PAL, kernal: :c64, datasette: true, board: :c64)

    # The NTSC C64 with the 6567R8 VIC-II.
    NTSC = Profile.new(name: "ntsc", vic_model: :mos6569, cia_model: :mos6526, sid_model: :mos6581,
                       region: Region::NTSC, kernal: :c64, datasette: true, board: :c64)

    # The NTSC C64C: the 8562, the 6567R8's HMOS successor, with the
    # C64C's CIAs and SID.
    NEW_NTSC = Profile.new(name: "newntsc", vic_model: :mos8565, cia_model: :mos6526a, sid_model: :mos8580,
                           region: Region::NTSC, kernal: :c64, datasette: true, board: :c64)

    # The first NTSC C64s, with the 6567R56A VIC-II.
    OLD_NTSC = Profile.new(name: "oldntsc", vic_model: :mos6569, cia_model: :mos6526, sid_model: :mos6581,
                           region: Region::NTSC_OLD, kernal: :c64, datasette: true, board: :c64)

    # The Drean C64 of Argentina, on PAL-N with the 6572 VIC-II.
    DREAN = Profile.new(name: "drean", vic_model: :mos6569, cia_model: :mos6526, sid_model: :mos6581,
                        region: Region::DREAN, kernal: :c64, datasette: true, board: :c64)

    # The portable SX-64: a PAL C64's chips with its own KERNAL, a 1541
    # built in as device 8 and no cassette port.
    SX64 = Profile.new(name: "sx64", vic_model: :mos6569, cia_model: :mos6526, sid_model: :mos6581,
                       region: Region::PAL, kernal: :sx64, datasette: false, board: :c64)

    # The PET 64, or Educator 64: a PAL C64's board in a PET's case, with
    # its own KERNAL and a green monochrome monitor built in.
    PET64 = Profile.new(name: "pet64", vic_model: :mos6569, cia_model: :mos6526, sid_model: :mos6581,
                        region: Region::PAL, kernal: :pet64, datasette: true, board: :pet64)

    ALL = [C64, C64C, NTSC, NEW_NTSC, OLD_NTSC, DREAN, SX64, PET64].freeze

    def self.named(name)
      model = ALL.find { |candidate| candidate.name == name }
      raise ArgumentError, "no C64 model named #{name}" if model.nil?

      model
    end

    # The model whose chips, region, KERNAL, datasette and board `machine`
    # has, or nil for none.
    def self.of(machine)
      ALL.find do |model|
        model.vic_model == machine.vic_model && model.cia_model == machine.cia_model &&
          model.sid_model == machine.sid_model && model.region == machine.region &&
          model.kernal == machine.kernal && model.datasette == machine.datasette && model.board == machine.board
      end
    end
  end
end
