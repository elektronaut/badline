# frozen_string_literal: true

module Badline
  class Plus4
    # The 264 series machines badline builds by name, after xplus4's
    # -model names, with the C116 as another name for the C16: one board
    # design with its RAM, its video standard and KERNAL, and whether the
    # Plus/4's own parts are fitted (the 3-plus-1 function ROMs, the 6551
    # ACIA and the user port's 6529).
    module Model
      Profile = Data.define(:name, :ram_kb, :ted, :kernal, :plus4_parts)

      PLUS4 = Profile.new(name: "plus4", ram_kb: 64, ted: Chips::TED::PAL, kernal: "plus4/kernal-pal.rom",
                          plus4_parts: true)
      PLUS4_NTSC = Profile.new(name: "plus4ntsc", ram_kb: 64, ted: Chips::TED::NTSC,
                               kernal: "plus4/kernal-ntsc.rom", plus4_parts: true)
      C16 = Profile.new(name: "c16", ram_kb: 16, ted: Chips::TED::PAL, kernal: "plus4/kernal-pal.rom",
                        plus4_parts: false)
      C16_NTSC = Profile.new(name: "c16ntsc", ram_kb: 16, ted: Chips::TED::NTSC, kernal: "plus4/kernal-ntsc.rom",
                             plus4_parts: false)

      ALL = [PLUS4, PLUS4_NTSC, C16, C16_NTSC].freeze

      # Other names a model goes by.
      ALIASES = { "c116" => "c16" }.freeze

      # The RAM sizes a machine can have, in K.
      RAM_SIZES = [16, 32, 64].freeze

      def self.named(name)
        model = ALL.find { |candidate| candidate.name == ALIASES.fetch(name, name) }
        raise ArgumentError, "no Plus/4 model named #{name}" if model.nil?

        model
      end
    end
  end
end
