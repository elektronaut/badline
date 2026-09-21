# frozen_string_literal: true

module Badline
  class SID
    # Waveform generator: a 24-bit phase accumulator and the shapers that
    # read it.
    #
    # The accumulator advances by the 16-bit frequency every cycle, so every
    # waveform is a pure function of the phase. Bit 23 drives hard sync and
    # the triangle fold, bit 19 clocks the noise LFSR.
    #
    # Combined waveforms are approximated by ANDing the selected shapers.
    # Real hardware bleeds charge between the bit lines, which only sampled
    # tables reproduce.
    class Waveform
      # All bits high at power up, odd ones stored inverted (SID/oscinit).
      POWER_ON_ACCUMULATOR = 0x555555

      # The LFSR refills to this when the test bit is released.
      NOISE_SEED = 0x7ffff8

      MSB = 0x800000

      attr_accessor :sync_source, :sync_dest
      attr_reader :accumulator, :shift_register, :frequency, :pulse_width

      def initialize
        @accumulator = POWER_ON_ACCUMULATOR
        @shift_register = NOISE_SEED
        @frequency = 0x0000
        @pulse_width = 0x000
        @selected = 0x0
        @test = false
        @ring = false
        @sync = false
        @msb_rising = false
        @sync_source = self
        @sync_dest = self
      end

      def sync? = @sync
      def msb_rising? = @msb_rising

      def frequency_low=(value)
        @frequency = (@frequency & 0xff00) | value
      end

      def frequency_high=(value)
        @frequency = (value << 8) | (@frequency & 0x00ff)
      end

      def pulse_width_low=(value)
        @pulse_width = (@pulse_width & 0xf00) | value
      end

      def pulse_width_high=(value)
        @pulse_width = ((value & 0x0f) << 8) | (@pulse_width & 0x0ff)
      end

      # The test bit clears the accumulator and the LFSR for as long as it is
      # held; releasing it refills the LFSR and restarts the oscillator.
      def control=(value)
        @selected = (value >> 4) & 0x0f
        @ring = value.anybits?(0x04)
        @sync = value.anybits?(0x02)
        test = value.anybits?(0x08)
        if test
          @accumulator = 0x000000
          @shift_register = 0x000000
        elsif @test
          @shift_register = NOISE_SEED
        end
        @test = test
      end

      def cycle!
        return if @test

        previous = @accumulator
        @accumulator = (previous + @frequency) & 0xffffff
        @msb_rising = previous.nobits?(MSB) && @accumulator.anybits?(MSB)
        clock_noise if previous.nobits?(0x080000) && @accumulator.anybits?(0x080000)
      end

      # Hard sync resets the next voice's accumulator when ours wraps. A
      # source that is itself synced on the cycle its own MSB rises does not
      # pass the sync on.
      def synchronize!
        return unless @msb_rising && @sync_dest.sync? &&
                      !(@sync && @sync_source.msb_rising?)

        @sync_dest.reset_accumulator
      end

      def reset_accumulator
        @accumulator = 0x000000
      end

      def output
        case @selected
        when 0x0 then 0x000
        when 0x1 then triangle
        when 0x2 then sawtooth
        when 0x4 then pulse
        when 0x8 then noise
        else combined
        end
      end

      def sawtooth = @accumulator >> 12

      # The upper half of the ramp is folded back down, shifted left one bit
      # to keep the full 12-bit range.
      def triangle
        folded = inverted? ? @accumulator ^ 0xffffff : @accumulator
        (folded >> 11) & 0xfff
      end

      def pulse
        @test || (@accumulator >> 12) >= @pulse_width ? 0xfff : 0x000
      end

      # Eight taps off the 23-bit LFSR, gathered into a 12-bit sample.
      def noise
        ((@shift_register & 0x400000) >> 11) |
          ((@shift_register & 0x100000) >> 10) |
          ((@shift_register & 0x010000) >> 7) |
          ((@shift_register & 0x002000) >> 5) |
          ((@shift_register & 0x000800) >> 4) |
          ((@shift_register & 0x000080) >> 1) |
          ((@shift_register & 0x000010) << 1) |
          ((@shift_register & 0x000004) << 2)
      end

      private

      def combined
        value = 0xfff
        value &= triangle if @selected.anybits?(0x1)
        value &= sawtooth if @selected.anybits?(0x2)
        value &= pulse    if @selected.anybits?(0x4)
        value &= noise    if @selected.anybits?(0x8)
        value
      end

      # TriXOR = !Saw & ((!V3 & Ring) ^ bit23), where V3 is the modulating
      # voice's MSB (SID/ringmod).
      def inverted?
        return false if @selected.anybits?(0x2)

        msb = @accumulator.anybits?(MSB)
        return msb unless @ring

        msb != @sync_source.accumulator.nobits?(MSB)
      end

      def clock_noise
        bit0 = ((@shift_register >> 22) ^ (@shift_register >> 17)) & 0x1
        @shift_register = ((@shift_register << 1) & 0x7fffff) | bit0
      end
    end
  end
end
