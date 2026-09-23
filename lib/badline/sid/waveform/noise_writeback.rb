# frozen_string_literal: true

module Badline
  class SID
    class Waveform
      # Noise combined with other waveforms: the output lines write back into
      # the LFSR.
      module NoiseWriteback
        # The LFSR bits the noise shaper reads, paired with the output bit each
        # one drives (Dag Lem's diagram in SID/noise-reset_new). A combined
        # waveform drives the same lines, so a bit held low there is written
        # back into the register.
        NOISE_TAPS = [[0x100000, 0x800], [0x040000, 0x400], [0x004000, 0x200],
                      [0x000800, 0x100], [0x000200, 0x080], [0x000020, 0x040],
                      [0x000004, 0x020], [0x000001, 0x010]].freeze

        private

        def write_shift_register(value)
          NOISE_TAPS.each { |bit, line| @shift_register &= ~bit if value.nobits?(line) }
        end

        # Releasing the test bit finishes the shift it interrupted: the old
        # waveform's output may be written back first, then a bit clocks in
        # over the forced-high bit 22.
        def release_test(previous)
          write_shift_register(shape(previous)) if release_writes_back?(previous, @selected)
          shift_noise(1)
        end

        # Which waveform changes write the old output back as the test bit
        # falls (SID/wb_testsuite, after libresidfp's do_writeback). Noise has
        # to have been combined before and still be selected after. Dropping to
        # noise alone writes nothing back unless all four were selected, nor
        # does changing to pulse+noise, nor, on the 6581, trading triangle for
        # sawtooth or back.
        def release_writes_back?(previous, selected)
          return false if previous <= 0x8 || selected < 0x8
          return false if selected == 0x8 && previous != 0xf
          return false if selected == 0xc

          !(@topbit_feedback && [previous & 0x3, selected & 0x3].sort == [0x1, 0x2])
        end
      end
    end
  end
end
