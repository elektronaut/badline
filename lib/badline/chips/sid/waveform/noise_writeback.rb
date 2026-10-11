# frozen_string_literal: true

module Badline
  class SID
    class Waveform
      # Noise combined with other waveforms: the output lines write back into
      # the LFSR, and what they write is not always what OSC3 reads.
      module NoiseWriteback
        # The LFSR bits the noise shaper reads, paired with the output bit each
        # one drives (Dag Lem's diagram in SID/noise-reset_new). A combined
        # waveform drives the same lines, so a bit held low there is written
        # back into the register.
        NOISE_TAPS = [[0x100000, 0x800], [0x040000, 0x400], [0x004000, 0x200],
                      [0x000800, 0x100], [0x000200, 0x080], [0x000020, 0x040],
                      [0x000004, 0x020], [0x000001, 0x010]].freeze

        # Pulse+noise with the pulse high: the noise lines next to the four
        # below them, which nothing drives, are pulled low. The OSC3 read and
        # the LFSR writeback see the same lines against different thresholds,
        # so they lose a different number of bits. The 8580's pair is the one
        # that reproduces SID/wf12nsr's pulse+noise row (it reads $f8, and the
        # writeback leaves $fc behind), and SID/wb_testsuite's C->9 and C->E
        # rows need that same $fc written at release. The 6581 reads $00 of a
        # full register (SID/wf12nsr's pulse+noise row) and pulls nothing
        # while the register holds: wb_testsuite's 8->C and C->C rows run
        # pulse+noise and leave the register alone. Its lines only land
        # part way through a shift (#write_back_shift).
        PULSE_NOISE_READ = { mos6581: 0x000, mos8580: 0xf80 }.freeze
        PULSE_NOISE_WRITE = { mos6581: 0xff0, mos8580: 0xfc0 }.freeze

        # What a 6581 writes back when the test bit falls with only pulse+noise
        # common to the old waveform and the new one (SID/wb_testsuite's D->C,
        # E->C, F->C and D->E rows).
        PULSE_NOISE_RELEASE = 0xf80

        private

        # What the lines write into the LFSR, against a lower threshold than
        # OSC3 reads them by: a line left high between two low ones reads high
        # (SID/noisewriteback's noise_writeback_test2) but is written low
        # (SID/wf12nsr's noise+triangle and noise+sawtooth rows).
        def write_back(selected, value)
          return value & ((value << 1) | (value >> 1)) unless selected == 0xc
          return 0x000 if @pulse.zero?

          noise & @pulse_noise_write
        end

        # What the lines write while the register is part way through a
        # shift, where the 6581's pulse+noise writes its output as read.
        def write_back_mid_shift(selected, value)
          return value if pulse_noise_mid_shift?(selected)

          write_back(selected, value)
        end

        def pulse_noise_mid_shift?(selected) = @topbit_feedback && selected == 0xc

        def write_shift_register(value)
          NOISE_TAPS.each { |bit, line| @shift_register &= ~bit if value.nobits?(line) }
        end

        # The second phase of a shift writes back by the test bit release
        # rule with the waveform left alone. The 6581's pulse+noise, which
        # that rule leaves out, writes its lines too (SID/wf12nsr's
        # pulse+noise row).
        def write_back_shift
          return unless pulse_noise_mid_shift?(@selected) || release_writes_back?(@selected, @selected)

          write_shift_register(write_back_mid_shift(@selected, @output))
        end

        # Setting the test bit starts the bleed, and stalls the register part
        # way through a shift, where a noise combination writes its output
        # back first, from the accumulator it had. SID/noiselfsrinit's
        # $f8/$80 pairs set the bit onto all four from noise alone, and
        # SID/wf12nsr's pulse+noise row sets it onto pulse+noise.
        def raise_test
          @shift_register_reset = @shift_register_reset_delay
          return unless @selected.anybits?(0x8) && combined?(@selected) && @shift_pipeline != 1

          write_shift_register(write_back_mid_shift(@selected, shape(@selected)))
        end

        # Releasing the test bit finishes the shift it interrupted: the old
        # waveform's output may be written back first, then a bit clocks in
        # over the forced-high bit 22.
        def release_test(previous)
          value = release_write(previous)
          write_shift_register(value) if value
          shift_noise(1)
        end

        # What the release writes over the taps, or nil. On the 6581, a change
        # that keeps only pulse+noise of the old waveform writes the lowest
        # noise lines low. On the 8580, a change from pulse+noise to all four
        # writes every line low.
        def release_write(previous)
          if @topbit_feedback
            return noise & PULSE_NOISE_RELEASE if previous != 0xc && (previous & @selected) == 0xc
          elsif previous == 0xc && @selected == 0xf
            return 0x000
          end
          write_back(previous, shape(previous)) if release_writes_back?(previous, @selected)
        end

        # Which waveform changes write the old output back as the test bit
        # falls (SID/wb_testsuite, after libresidfp's do_writeback). Noise has
        # to have been combined before and still be combined after. Nothing
        # is written back on changing to pulse+noise or from pulse+noise to
        # sawtooth+noise, nor, on the 6581, on trading triangle for sawtooth
        # or back.
        def release_writes_back?(previous, selected)
          return false if previous <= 0x8 || selected <= 0x8
          return false if selected == 0xc || (previous == 0xc && selected == 0xa)

          !(@topbit_feedback && [previous & 0x3, selected & 0x3].sort == [0x1, 0x2])
        end
      end
    end
  end
end
