# frozen_string_literal: true

module Badline
  class SID
    # The SID's multimode filter: a state-variable design integrating low-,
    # band- and high-pass in parallel, with the mixer and master volume on
    # its output, and the C64 board's own RC network after that.
    #
    # Voices are routed through it or around it per the RES/FILT register,
    # and the outputs selected by MODE/VOL are summed back together with the
    # unfiltered ones.
    class Filter
      # Cutoff frequency in Hz at each chip's breakpoints. The 6581 curve was
      # sampled from a real chip by reSID and bends sharply around $300; the
      # 8580's is close to a straight line from 0 to 12.5 kHz. The curve
      # between breakpoints is interpolated linearly; reSID fits a spline, so
      # the two differ by a few Hz mid-segment.
      CUTOFF_POINTS = {
        mos6581: [[0, 220], [128, 230], [256, 250], [384, 300],
                  [512, 420], [640, 780], [768, 1600], [832, 2300],
                  [896, 3200], [960, 4300], [1024, 5000], [1088, 5400],
                  [1152, 5800], [1216, 6000], [1280, 6200], [1344, 6400],
                  [1408, 6600], [1472, 6800], [1536, 7000], [1600, 7200],
                  [1664, 7400], [1728, 7600], [1792, 7800], [1856, 8000],
                  [1920, 8200], [1984, 8400], [2047, 8600]].freeze,
        mos8580: [[0, 0], [128, 800], [256, 1600], [384, 2500],
                  [512, 3300], [640, 4100], [768, 4800], [896, 5600],
                  [1024, 6500], [1152, 7500], [1280, 8400], [1408, 9200],
                  [1536, 9800], [1664, 10_500], [1792, 11_000],
                  [1920, 11_700], [2047, 12_500]].freeze
      }.freeze

      # 2^20 / 1 MHz, so one cycle of integration is a plain shift.
      SCALE = (2**20) / 1_000_000.0

      # The integrator goes unstable above ~16 kHz at a one-cycle step.
      W0_MAX = (2 * Math::PI * 16_000 * SCALE).to_i

      def self.build_w0(points)
        table = Array.new(2048)
        points.each_cons(2) do |(fc0, hz0), (fc1, hz1)|
          (fc0..fc1).each do |register|
            hz = hz0 + (((hz1 - hz0) * (register - fc0)).to_f / (fc1 - fc0))
            table[register] = [(2 * Math::PI * hz * SCALE).to_i, W0_MAX].min
          end
        end
        table.freeze
      end
      private_class_method :build_w0

      W0 = CUTOFF_POINTS.transform_values { |points| build_w0(points) }.freeze

      # 1024/Q, with Q sweeping from 0.707 up to 1.707 across the register.
      RESONANCE = (0x0..0xf).map { |res| (1024.0 / (0.707 + (res / 15.0))).to_i }.freeze

      # The mixer's own input DC offset, derived by reSID from the 6581's
      # zero-volume and full-volume output levels. The 8580 has none.
      MIXER_DC = { mos6581: -((0xfff * 0xff) / 18) >> 7, mos8580: 0 }.freeze

      # The RC network between the SID's audio pin and the C64's output jack:
      # a 10kΩ/1000pF low-pass at ~16 kHz, then a 1kΩ/10µF high-pass at
      # ~16 Hz that strips the 6581's DC offset off the mix.
      class External
        W0_LOWPASS = (100_000 * SCALE).round
        W0_HIGHPASS = (100 * SCALE).round

        attr_reader :output

        def initialize
          @lowpass = 0
          @highpass = 0
          @output = 0
        end

        def cycle!(input)
          delta_lowpass = ((W0_LOWPASS >> 8) * (input - @lowpass)) >> 12
          delta_highpass = (W0_HIGHPASS * (@lowpass - @highpass)) >> 20
          @output = @lowpass - @highpass
          @lowpass += delta_lowpass
          @highpass += delta_highpass
          @output
        end
      end

      attr_reader :model, :cutoff, :routing, :mode, :volume, :lowpass, :bandpass, :highpass

      def initialize(model: :mos6581)
        @model = model
        @w0_table = W0.fetch(model)
        @mixer_dc = MIXER_DC.fetch(model)
        @external = External.new
        reset
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
        @w0 = @w0_table[@cutoff]
      end

      def voice3_off? = @voice3_off

      def cycle!(voices)
        route(voices)
        @bandpass -= (@w0 * @highpass) >> 20
        @lowpass -= (@w0 * @bandpass) >> 20
        @highpass = ((@bandpass * @resonance) >> 10) - @lowpass - @input
        @external.cycle!(mix)
      end

      # The SID's own audio pin, before the board's RC network.
      def mix = (@unfiltered + filtered + @mixer_dc) * @volume

      def output = @external.output

      private

      def reset
        @cutoff = 0x000
        @routing = 0x0
        @mode = 0x0
        @volume = 0x0
        @voice3_off = false
        @w0 = @w0_table[0]
        @resonance = RESONANCE[0]
        @lowpass = @bandpass = @highpass = 0
        @input = @unfiltered = 0
      end

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
