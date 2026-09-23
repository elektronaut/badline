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
        # rows need that same $fc written at release. On the 6581 the read is
        # the $fc of SID/wf12nsr's readme (VICE bug #1037), and the writeback
        # pulls nothing: wb_testsuite's 8/9/A/B->C rows run pulse+noise and
        # leave the register alone.
        PULSE_NOISE_READ = { mos6581: 0xfc0, mos8580: 0xf80 }.freeze
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
          return value if value.zero?

          noise & @pulse_noise_write
        end

        def write_shift_register(value)
          NOISE_TAPS.each { |bit, line| @shift_register &= ~bit if value.nobits?(line) }
        end

        # Releasing the test bit finishes the shift it interrupted: the old
        # waveform's output may be written back first, then a bit clocks in
        # over the forced-high bit 22. On the 6581, a change that keeps only
        # pulse+noise of the old waveform writes the lowest noise lines low.
        def release_test(previous)
          if @topbit_feedback && previous != 0xc && (previous & @selected) == 0xc
            write_shift_register(noise & PULSE_NOISE_RELEASE)
          elsif release_writes_back?(previous, @selected)
            write_shift_register(write_back(previous, shape(previous)))
          end
          shift_noise(1)
        end

        # Which waveform changes write the old output back as the test bit
        # falls (SID/wb_testsuite, after libresidfp's do_writeback). Noise has
        # to have been combined before and still be selected after. Dropping
        # to noise alone writes nothing back unless all four were selected,
        # nor does changing to pulse+noise or from pulse+noise to
        # sawtooth+noise, nor, on the 6581, trading triangle for sawtooth or
        # back.
        def release_writes_back?(previous, selected)
          return false if previous <= 0x8 || selected < 0x8
          return previous == 0xf if selected == 0x8
          return false if selected == 0xc || (previous == 0xc && selected == 0xa)

          !(@topbit_feedback && [previous & 0x3, selected & 0x3].sort == [0x1, 0x2])
        end
      end
    end
  end
end
