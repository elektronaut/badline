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
    # Selecting more than one waveform shorts the shapers onto the lines the
    # oscillator itself reads back, so a combined waveform is not only a
    # shape: a low top bit reaches the accumulator MSB through the sawtooth
    # switch, and noise in the mix is written back into the LFSR. The shape
    # itself is approximated by ANDing the shapers — the analog result only
    # comes out of sampled tables.
    #
    # With nothing selected the DAC input floats, holding the last value
    # driven onto it until the charge drains away.
    class Waveform
      # All bits high at power up, odd ones stored inverted (SID/oscinit).
      POWER_ON_ACCUMULATOR = 0x555555

      # Holding the test bit bleeds every LFSR bit high; the power-on state is
      # one shift further on, which is what releasing the bit leaves behind.
      SHIFT_REGISTER_RESET = 0x7fffff
      NOISE_SEED = 0x7ffffe

      # Cycles the test bit needs to bleed the LFSR high; SID/bitfade reads
      # delaynoise at ~$8000. SID/wf12nsr's slow reset allows a second for it,
      # its fast one (SID/noise-reset_new) does not wait at all.
      SHIFT_REGISTER_RESET_DELAY = 0x8000

      # Cycles the floating DAC input holds its charge (SID/osc3-wave0).
      FLOATING_OUTPUT_TTL = 0x4000

      MSB = 0x800000

      # The LFSR bits the noise shaper reads, paired with the output bit each
      # one drives (Dag Lem's diagram in SID/noise-reset_new). A combined
      # waveform drives the same lines, so a bit held low there is written
      # back into the register.
      NOISE_TAPS = [[0x100000, 0x800], [0x040000, 0x400], [0x004000, 0x200],
                    [0x000800, 0x100], [0x000200, 0x080], [0x000020, 0x040],
                    [0x000004, 0x020], [0x000001, 0x010]].freeze

      attr_accessor :sync_source, :sync_dest
      attr_reader :accumulator, :shift_register, :frequency, :pulse_width

      def initialize(model: :mos6581)
        @topbit_feedback = model != :mos8580
        @accumulator = POWER_ON_ACCUMULATOR
        @shift_register = NOISE_SEED
        @shift_register_reset = 0
        @frequency = 0x0000
        @pulse_width = 0x000
        @selected = 0x0
        @test = false
        @ring = false
        @sync = false
        @msb_rising = false
        @floating = 0x000
        @floating_ttl = 0
        @output = 0x000
        @stale = true
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
        @stale = true
      end

      def pulse_width_high=(value)
        @pulse_width = ((value & 0x0f) << 8) | (@pulse_width & 0x0ff)
        @stale = true
      end

      # The test bit clears the accumulator and stalls the LFSR half way
      # through a shift, holding bit 22 high while its bits bleed up.
      def control=(value)
        previous = @selected
        @selected = (value >> 4) & 0x0f
        @ring = value.anybits?(0x04)
        @sync = value.anybits?(0x02)
        test = value.anybits?(0x08)
        if test
          @accumulator = 0x000000
          @shift_register_reset = SHIFT_REGISTER_RESET_DELAY unless @test
        elsif @test
          release_test(previous)
        end
        @test = test
        @stale = true
      end

      def cycle!
        latch_output
        @test ? bleed_shift_register : advance
        @stale = true
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
        @stale = true
      end

      # Held for the rest of the cycle once computed, so the filter, OSC3 and
      # the oscillator's own feedback all see one value per cycle.
      def output
        return @output unless @stale

        @stale = false
        @output = @selected.zero? ? @floating : shape(@selected)
      end

      def sawtooth = @accumulator >> 12

      # The upper half of the ramp is folded back down, shifted left one bit
      # to keep the full 12-bit range.
      def triangle(selected = @selected)
        folded = inverted?(selected) ? @accumulator ^ 0xffffff : @accumulator
        (folded >> 11) & 0xfff
      end

      def pulse
        @test || (@accumulator >> 12) >= @pulse_width ? 0xfff : 0x000
      end

      # Eight taps off the 23-bit LFSR, gathered into a 12-bit sample.
      def noise
        ((@shift_register & 0x100000) >> 9) |
          ((@shift_register & 0x040000) >> 8) |
          ((@shift_register & 0x004000) >> 5) |
          ((@shift_register & 0x000800) >> 3) |
          ((@shift_register & 0x000200) >> 2) |
          ((@shift_register & 0x000020) << 1) |
          ((@shift_register & 0x000004) << 3) |
          ((@shift_register & 0x000001) << 4)
      end

      private

      def shape(selected)
        case selected
        when 0x1 then triangle(selected)
        when 0x2 then sawtooth
        when 0x4 then pulse
        when 0x8 then noise
        else combined(selected)
        end
      end

      def combined(selected)
        value = 0xfff
        value &= triangle(selected) if selected.anybits?(0x1)
        value &= sawtooth           if selected.anybits?(0x2)
        value &= pulse              if selected.anybits?(0x4)
        value &= noise              if selected.anybits?(0x8)
        value
      end

      # More than one bit set in the selection.
      def combined?(selected) = selected.anybits?(selected - 1)

      # The one point in the cycle where the waveform selector drives the DAC:
      # either it latches a fresh value, or nothing drives the line and the
      # charge already on it drains a little further.
      def latch_output
        value = output
        if @selected.zero?
          @floating = 0x000 if @floating_ttl.positive? && (@floating_ttl -= 1).zero?
          return
        end

        @floating = value
        @floating_ttl = FLOATING_OUTPUT_TTL
        feed_back(value) if combined?(@selected) && !@test
      end

      # A zero on the shared output lines travels back into the oscillator:
      # through the sawtooth switch it clears the accumulator MSB on the next
      # cycle, and with noise selected it lands in the LFSR, where a bit
      # pulled low can never come back. The 8580 buffers the top bit behind a
      # flip-flop before the sawtooth switch, so only the LFSR sees it.
      def feed_back(value)
        @accumulator &= ~MSB if @topbit_feedback && @selected.anybits?(0x2) && value.nobits?(0x800)
        write_shift_register(value) if @selected.anybits?(0x8)
      end

      def write_shift_register(value)
        NOISE_TAPS.each { |bit, line| @shift_register &= ~bit if value.nobits?(line) }
      end

      # Releasing the test bit finishes the shift it interrupted: whatever the
      # waveform selector still holds on the output lines is written back
      # first, then a bit clocks in over the forced-high bit 22.
      def release_test(previous)
        write_shift_register(combined(previous)) if previous.anybits?(0x8) && combined?(previous)
        shift_noise(1)
      end

      def advance
        previous = @accumulator
        @accumulator = (previous + @frequency) & 0xffffff
        @msb_rising = previous.nobits?(MSB) && @accumulator.anybits?(MSB)
        shift_noise if previous.nobits?(0x080000) && @accumulator.anybits?(0x080000)
      end

      def bleed_shift_register
        return unless @shift_register_reset.positive?

        @shift_register = SHIFT_REGISTER_RESET if (@shift_register_reset -= 1).zero?
      end

      # Bit 0 feeds back bits 22 and 17, with the test bit forcing bit 22 high.
      def shift_noise(forced = 0)
        bit0 = ((@shift_register >> 22) | forced) ^ (@shift_register >> 17)
        @shift_register = ((@shift_register << 1) & 0x7fffff) | (bit0 & 0x1)
      end

      # TriXOR = !Saw & ((!V3 & Ring) ^ bit23), where V3 is the modulating
      # voice's MSB (SID/ringmod).
      def inverted?(selected)
        return false if selected.anybits?(0x2)

        msb = @accumulator.anybits?(MSB)
        return msb unless @ring

        msb != @sync_source.accumulator.nobits?(MSB)
      end
    end
  end
end
