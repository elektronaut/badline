# frozen_string_literal: true

module Badline
  class CBM2
    class P500
      # The P500s badline builds by name: the 510 of xcbm5x0's -model, PAL
      # with the 6569 and NTSC with the 6567R8, each with its own region's
      # mains unless told otherwise. Both have 128K of RAM, segments 0 and 1,
      # and the one KERNAL and BASIC.
      module Model
        Profile = Data.define(:name, :region) do
          def ram_kb = RAM_SEGMENTS.length * 64
        end

        M510 = Profile.new(name: "510", region: Region::PAL)
        M510_NTSC = Profile.new(name: "510ntsc", region: Region::NTSC)

        ALL = [M510, M510_NTSC].freeze
        DEFAULT = "510"

        RAM_SEGMENTS = [0, 1].freeze

        # 901234-02, the KERNAL xcbm5x0 runs, and its BASIC 128, 901236-02
        # and 901235-02.
        KERNALS = { "02" => "cbm2/p500-kernal.rom" }.freeze
        BASIC = "cbm2/p500-basic.rom"

        def self.named(name)
          model = ALL.find { |candidate| candidate.name == name }
          raise ArgumentError, "no P500 model named #{name}" if model.nil?

          model
        end

        def self.include?(name) = ALL.any? { |model| model.name == name }
      end
    end
  end
end
