# frozen_string_literal: true

module Badline
  class PET
    # The PETs and CBMs badline builds by name, after xpet's -model names:
    # the board's RAM, its stock ROM set and video, and whether the 8096's
    # 64K board is fitted.
    #
    # +video+ is :discrete, the fixed 40-column, 60 Hz generator of the
    # 2001 and 3000 series, :crtc40 or :crtc80, a 6545 the editor ROM
    # programs. The CRTC editors come in a 50 Hz and a 60 Hz version, and
    # the discrete ones run at 60 Hz alone, so +editor_50hz+ and
    # +editor_60hz+ name the same ROM there.
    #
    # The 2001's 1K of screen RAM repeats four times through $8000-$8FFF.
    # Later boards decode $8000-$87FF alone, the 40-column ones with their
    # 1K twice over and the 80-column ones with 2K.
    module Model
      Profile = Data.define(:name, :ram_kb, :basic, :editor_50hz, :editor_60hz, :kernal, :characters, :keyboard,
                            :video, :expansion) do
        def crtc? = video != :discrete

        def editor(refresh_hz) = refresh_hz == 50 ? editor_50hz : editor_60hz

        def screen_bytes = video == :crtc80 ? 0x800 : 0x400

        # How many pages from $8000 on the screen RAM answers in.
        def screen_pages = name == "2001" ? 0x10 : 0x08

        # The BASIC 1 KERNAL keeps its keyboard buffer and jiffy clock in
        # page 2; BASIC 2 and 4 keep them where each other does.
        def basic1? = basic == "pet/basic1.rom"

        # Where the KERNAL keeps its IEEE-488 primitives
        # (KernalTrap::IEEELayout).
        def trap_layout
          case kernal
          when "pet/kernal1.rom" then KernalTrap::PET_BASIC1_LAYOUT
          when "pet/kernal2.rom" then KernalTrap::PET_BASIC2_LAYOUT
          else KernalTrap::PET_BASIC4_LAYOUT
          end
        end
      end

      PET2001 = Profile.new(name: "2001", ram_kb: 8, basic: "pet/basic1.rom", editor_50hz: "pet/editor1.rom",
                            editor_60hz: "pet/editor1.rom", kernal: "pet/kernal1.rom",
                            characters: "pet/characters1.rom", keyboard: :graphics, video: :discrete,
                            expansion: false)
      PET3032 = Profile.new(name: "3032", ram_kb: 32, basic: "pet/basic2.rom", editor_50hz: "pet/editor2-n.rom",
                            editor_60hz: "pet/editor2-n.rom", kernal: "pet/kernal2.rom",
                            characters: "pet/characters2.rom", keyboard: :graphics, video: :discrete,
                            expansion: false)
      PET3032B = Profile.new(name: "3032b", ram_kb: 32, basic: "pet/basic2.rom", editor_50hz: "pet/editor2-b.rom",
                             editor_60hz: "pet/editor2-b.rom", kernal: "pet/kernal2.rom",
                             characters: "pet/characters2.rom", keyboard: :business, video: :discrete,
                             expansion: false)
      PET4032 = Profile.new(name: "4032", ram_kb: 32, basic: "pet/basic4.rom",
                            editor_50hz: "pet/editor4-40-n-50hz.rom", editor_60hz: "pet/editor4-40-n-60hz.rom",
                            kernal: "pet/kernal4.rom", characters: "pet/characters2.rom", keyboard: :graphics,
                            video: :crtc40, expansion: false)
      CBM8032 = Profile.new(name: "8032", ram_kb: 32, basic: "pet/basic4.rom",
                            editor_50hz: "pet/editor4-80-b-50hz.rom", editor_60hz: "pet/editor4-80-b-60hz.rom",
                            kernal: "pet/kernal4.rom", characters: "pet/characters2.rom", keyboard: :business,
                            video: :crtc80, expansion: false)
      CBM8096 = Profile.new(name: "8096", ram_kb: 32, basic: "pet/basic4.rom",
                            editor_50hz: "pet/editor4-80-b-50hz.rom", editor_60hz: "pet/editor4-80-b-60hz.rom",
                            kernal: "pet/kernal4.rom", characters: "pet/characters2.rom", keyboard: :business,
                            video: :crtc80, expansion: true)

      ALL = [PET2001, PET3032, PET3032B, PET4032, CBM8032, CBM8096].freeze

      DEFAULT = "8032"

      # The RAM a board can have, in K, below $8000: the 3008, 3016 and
      # 4016 are 3032s and 4032s with less of it.
      RAM_SIZES = [4, 8, 16, 32].freeze

      def self.named(name)
        model = ALL.find { |candidate| candidate.name == name }
        raise ArgumentError, "no PET model named #{name}" if model.nil?

        model
      end
    end
  end
end
