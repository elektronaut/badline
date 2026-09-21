# frozen_string_literal: true

module Badline
  class SID
    # One of the three voices: a waveform generator amplitude-modulated by
    # its envelope.
    #
    # The 6581 waveform DAC swings around a midpoint rather than zero, so
    # even a silent voice carries DC_OFFSET into the mixer.
    class Voice
      WAVE_ZERO = 0x380
      DC_OFFSET = 0x800 * 0xff

      attr_reader :waveform, :envelope

      def initialize
        @waveform = Waveform.new
        @envelope = Envelope.new
      end

      def control=(value)
        @waveform.control = value
        @envelope.control = value
      end

      def cycle!
        @envelope.cycle!
        @waveform.cycle!
      end

      def output
        ((@waveform.output - WAVE_ZERO) * @envelope.output) + DC_OFFSET
      end
    end
  end
end
