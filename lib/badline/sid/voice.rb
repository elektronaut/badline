# frozen_string_literal: true

module Badline
  class SID
    # One of the three voices: a waveform generator amplitude-modulated by
    # its envelope.
    #
    # The 6581 waveform DAC swings around a midpoint well above ground, so
    # even a silent voice carries a large DC offset into the mixer. The
    # 8580's is centred and carries none.
    class Voice
      WAVE_ZERO = { mos6581: 0x380, mos8580: 0x800 }.freeze
      DC_OFFSET = { mos6581: 0x800 * 0xff, mos8580: 0 }.freeze

      attr_reader :waveform, :envelope

      def initialize(model: :mos6581)
        @waveform = Waveform.new(model:)
        @envelope = Envelope.new
        @wave_zero = WAVE_ZERO.fetch(model)
        @dc_offset = DC_OFFSET.fetch(model)
      end

      def control=(value)
        @waveform.control = value
        @envelope.control = value
      end

      def cycle!
        @envelope.cycle!
        @waveform.cycle!
      end

      def fast_forward(cycles)
        @envelope.fast_forward(cycles)
        @waveform.fast_forward(cycles)
      end

      def output
        ((@waveform.output - @wave_zero) * @envelope.output) + @dc_offset
      end
    end
  end
end
