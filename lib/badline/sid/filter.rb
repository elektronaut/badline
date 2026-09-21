# frozen_string_literal: true

module Badline
  class SID
    # The 6581 multimode filter: a state-variable design integrating low-,
    # band- and high-pass in parallel, with the mixer and master volume on
    # its output.
    #
    # Voices are routed through it or around it per the RES/FILT register,
    # and the outputs selected by MODE/VOL are summed back together with the
    # unfiltered ones.
    class Filter
      # Cutoff frequency in Hz at the 6581's breakpoints, sampled from a real
      # chip by reSID. The curve between them is interpolated linearly;
      # reSID fits a spline, so the two differ by a few Hz mid-segment.
      CUTOFF_POINTS = [[0, 220], [128, 230], [256, 250], [384, 300],
                       [512, 420], [640, 780], [768, 1600], [832, 2300],
                       [896, 3200], [960, 4300], [1024, 5000], [1088, 5400],
                       [1152, 5800], [1216, 6000], [1280, 6200], [1344, 6400],
                       [1408, 6600], [1472, 6800], [1536, 7000], [1600, 7200],
                       [1664, 7400], [1728, 7600], [1792, 7800], [1856, 8000],
                       [1920, 8200], [1984, 8400], [2047, 8600]].freeze

      # 2^20 / 1 MHz, so one cycle of integration is a plain shift.
      SCALE = (2**20) / 1_000_000.0

      # The integrator goes unstable above ~16 kHz at a one-cycle step.
      W0_MAX = (2 * Math::PI * 16_000 * SCALE).to_i

      W0 = begin
        table = Array.new(2048)
        CUTOFF_POINTS.each_cons(2) do |(fc0, hz0), (fc1, hz1)|
          (fc0..fc1).each do |fc|
            hz = hz0 + (((hz1 - hz0) * (fc - fc0)).to_f / (fc1 - fc0))
            table[fc] = [(2 * Math::PI * hz * SCALE).to_i, W0_MAX].min
          end
        end
        table.freeze
      end

      # 1024/Q, with Q sweeping from 0.707 up to 1.707 across the register.
      RESONANCE = (0x0..0xf).map { |res| (1024.0 / (0.707 + (res / 15.0))).to_i }.freeze

      # The mixer's own input DC offset, derived by reSID from the 6581's
      # zero-volume and full-volume output levels.
      MIXER_DC = -((0xfff * 0xff) / 18) >> 7

      attr_reader :cutoff, :routing, :mode, :volume, :lowpass, :bandpass, :highpass

      def initialize
        @cutoff = 0x000
        @routing = 0x0
        @mode = 0x0
        @volume = 0x0
        @voice3_off = false
        @w0 = W0[0]
        @resonance = RESONANCE[0]
        @lowpass = @bandpass = @highpass = 0
        @input = @unfiltered = 0
      end

      def write(reg, value)
        case reg
        when 0x15 then self.cutoff = (@cutoff & 0x7f8) | (value & 0x07)
        when 0x16 then self.cutoff = (value << 3) | (@cutoff & 0x007)
        when 0x17 then write_resonance(value)
        when 0x18 then write_mode_volume(value)
        end
      end

      def cutoff=(value)
        @cutoff = value & 0x7ff
        @w0 = W0[@cutoff]
      end

      def voice3_off? = @voice3_off

      def cycle!(voices)
        route(voices)
        @bandpass -= (@w0 * @highpass) >> 20
        @lowpass -= (@w0 * @bandpass) >> 20
        @highpass = ((@bandpass * @resonance) >> 10) - @lowpass - @input
      end

      def output
        (@unfiltered + filtered + MIXER_DC) * @volume
      end

      private

      def write_resonance(value)
        @routing = value & 0x0f
        @resonance = RESONANCE[(value >> 4) & 0x0f]
      end

      def write_mode_volume(value)
        @volume = value & 0x0f
        @mode = (value >> 4) & 0x07
        @voice3_off = value.anybits?(0x80)
      end

      def route(voices)
        @input = 0
        @unfiltered = 0
        voices.each_with_index do |voice, i|
          if @routing.anybits?(1 << i)
            @input += voice.output >> 7
          else
            @unfiltered += bypass(voice, i)
          end
        end
      end

      # Voice 3 is silenced by MODE/VOL bit 7 only while it bypasses the
      # filter.
      def bypass(voice, index)
        return 0 if index == 2 && @voice3_off

        voice.output >> 7
      end

      def filtered
        value = 0
        value += @lowpass  if @mode.anybits?(0x1)
        value += @bandpass if @mode.anybits?(0x2)
        value += @highpass if @mode.anybits?(0x4)
        value
      end
    end
  end
end
