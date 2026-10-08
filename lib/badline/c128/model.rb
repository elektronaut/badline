# frozen_string_literal: true

module Badline
  class C128
    # The C128s badline builds by name: the chips each board has, and its
    # video standard. The plastic C128D is a "c128" board with a 1571 built
    # in. A VDC on either board can have 16K or 64K of RAM.
    module Model
      Profile = Data.define(:name, :vic_model, :cia_model, :sid_model, :region, :vdc_model, :vdc_ram_kb)

      # The C128 and the plastic C128D, PAL: the 8566 VIC-IIe, 6526 CIAs,
      # the 6581 SID and the 8563 VDC with 16K.
      C128 = Profile.new(name: "c128", vic_model: :mos8566, cia_model: :mos6526, sid_model: :mos6581,
                         region: Region::PAL, vdc_model: :mos8563, vdc_ram_kb: 16)

      # The NTSC C128, with the 8564.
      C128_NTSC = Profile.new(name: "c128ntsc", vic_model: :mos8564, cia_model: :mos6526, sid_model: :mos6581,
                              region: Region::NTSC, vdc_model: :mos8563, vdc_ram_kb: 16)

      # The metal C128DCR, PAL: 6526A CIAs, the 8580 SID and the 8568 VDC
      # with 64K.
      DCR = Profile.new(name: "c128dcr", vic_model: :mos8566, cia_model: :mos6526a, sid_model: :mos8580,
                        region: Region::PAL, vdc_model: :mos8568, vdc_ram_kb: 64)

      # The NTSC C128DCR, with the 8564.
      DCR_NTSC = Profile.new(name: "c128dcrntsc", vic_model: :mos8564, cia_model: :mos6526a, sid_model: :mos8580,
                             region: Region::NTSC, vdc_model: :mos8568, vdc_ram_kb: 64)

      ALL = [C128, C128_NTSC, DCR, DCR_NTSC].freeze

      def self.named(name)
        model = ALL.find { |candidate| candidate.name == name }
        raise ArgumentError, "no C128 model named #{name}" if model.nil?

        model
      end
    end
  end
end
