# frozen_string_literal: true

module Badline
  class CBM2
    # The B series models badline builds by name, after xcbm2's -model
    # names: the segments the RAM board fills, the BASIC that fits it, the
    # character ROM, and whether the board's PC7 jumper tells the editor
    # it drives the 700's monitor.
    module Model
      Profile = Data.define(:name, :ram_segments, :basic, :characters, :high_profile) do
        def ram_kb = ram_segments.length * 64
      end

      M610 = Profile.new(name: "610", ram_segments: [1, 2].freeze, basic: "cbm2/basic128.rom",
                         characters: "cbm2/characters-600.rom", high_profile: false)
      M620 = Profile.new(name: "620", ram_segments: [1, 2, 3, 4].freeze, basic: "cbm2/basic256.rom",
                         characters: "cbm2/characters-600.rom", high_profile: false)
      M710 = Profile.new(name: "710", ram_segments: [1, 2].freeze, basic: "cbm2/basic128.rom",
                         characters: "cbm2/characters-700.rom", high_profile: true)
      M720 = Profile.new(name: "720", ram_segments: [1, 2, 3, 4].freeze, basic: "cbm2/basic256.rom",
                         characters: "cbm2/characters-700.rom", high_profile: true)

      ALL = [M610, M620, M710, M720].freeze
      DEFAULT = "610"

      # The KERNALs a B series board takes: 901244-04a, VICE's, and
      # 901244-03b, the 1983 release.
      KERNALS = { "04a" => "cbm2/kernal-04a.rom", "03b" => "cbm2/kernal-03b.rom" }.freeze

      def self.named(name)
        model = ALL.find { |candidate| candidate.name == name }
        raise ArgumentError, "no CBM-II model named #{name}" if model.nil?

        model
      end

      # The BASIC +model+ runs with +kernal+: BASIC 128 of the 1983
      # release, 02b, with 03b.
      def self.basic(model, kernal)
        kernal == "03b" && model.basic == "cbm2/basic128.rom" ? "cbm2/basic128-02b.rom" : model.basic
      end
    end
  end
end
