# frozen_string_literal: true

require "badline/chips/ted/sound/output"

module Badline
  module Chips
    class TED
      # The TED's sound: two voices, the second a square wave or noise.
      # Voice 1's 10-bit frequency is $FF0E with $FF12 bits 0-1 above it,
      # voice 2's $FF0F with $FF10 bits 0-1. $FF11 holds the volume in bits
      # 0-3 (0 silent, 8 and above the loudest), voice 1 on in bit 4, voice
      # 2's square wave in bit 5 and its noise in bit 6 (the square wins if
      # both are set), and the reload bit in bit 7.
      #
      # Each voice counts once every 4 cycles, and its output toggles every
      # 1023 - x counts for a frequency x, so a square wave of the clock
      # over 8 * (1023 - x). $3FF counts 1,024 between toggles, and $3FE
      # stops the voice after its next toggle, with its output high. A new
      # frequency takes hold at the next toggle. The voices count whether
      # they are on or not.
      #
      # The noise is an 8-bit shift register that shifts at each of voice
      # 2's toggles: bits 1, 4, 5 and 7 XORed go in at bit 0, and bit 1 is
      # the noise's output.
      #
      # While the reload bit is set, the counters hold at their frequencies,
      # the outputs stay high and the noise's register holds all ones, with
      # the noise silent. Writing it clear starts each voice on a full high
      # half-wave. Samples play this way, with the voices held high and the
      # volume as a 9-level D/A converter.
      #
      # The output takes a level from the volume and how many voices are on
      # and high. The levels are measured from xplus4 recordings, whose two
      # voices together come out above twice one.
      #
      # The voices catch up to the current cycle whenever a write lands, the
      # samples are drained or #catch_up! asks, whether or not #record
      # collects the output, so their state doesn't depend on whether the
      # host plays it.
      class Sound
        VOICES = 2
        CYCLES_PER_COUNT = 4

        # The frequency that stops a voice with its output high.
        HELD = 0x3fe

        NOISE_TAPS = 0xb2
        NOISE_PERIOD = 255

        # The output's level for each volume 0-8, with no voice, one voice
        # and both voices high.
        LEVELS = [
          0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 586, 1610, 2634, 3658, 4682, 5706, 6730, 7754,
          0, 1172, 3284, 5526, 7984, 10_658, 13_548, 16_654, 19_976
        ].freeze

        # Far enough ahead that a voice stopped at $3FE, or held by the
        # reload bit, never toggles.
        NEVER = 1 << 60

        attr_reader :volume, :control

        # `clock` answers the machine's cycles, `clock_hz` the rate they run at.
        def initialize(clock, clock_hz)
          @clock = clock
          @clock_hz = clock_hz
          @output = nil
          @time = 0
          @frequencies = [0, 0]
          @intervals = [0, 0]
          @phases = [1, 1]
          @next_toggles = [0, 0]
          power_on!
        end

        def model = :mos7360

        # The power-on state: every register clear, both voices starting on
        # a high half-wave and the noise's register full of ones.
        def power_on!
          now = @clock.cycles
          run_to(now)
          @volume = 0
          @control = 0
          @reloading = false
          @noise = 0xff
          VOICES.times do |voice|
            @frequencies[voice] = 0
            @intervals[voice] = interval_for(0)
            @phases[voice] = 1
            @next_toggles[voice] = now + @intervals[voice]
          end
          @level = level_now
        end

        # Starts collecting the output, averaged down to `rate` samples a
        # second, for #drain_samples. `clock_hz` is the rate the cycles are
        # taken to run at.
        def record(rate:, clock_hz: @clock_hz)
          run_to(@clock.cycles)
          @output = Output.new(clock_hz:, rate:, level: @level)
        end

        def recording? = !@output.nil?

        # Runs the voices up to the current cycle.
        def catch_up! = run_to(@clock.cycles)

        # The samples recorded since the last drain.
        def drain_samples
          output = @output
          return [] if output.nil?

          run_to(@clock.cycles)
          output.drain
        end

        # A write to $FF0E-$FF12, which takes hold from the next cycle.
        def write(register, value)
          run_to(@clock.cycles + 1)
          case register
          when 0x0e then tune(0, (@frequencies[0] & 0x300) | value)
          when 0x0f then tune(1, (@frequencies[1] & 0x300) | value)
          when 0x10 then tune(1, (@frequencies[1] & 0xff) | ((value & 0x03) << 8))
          when 0x11 then write_control(value)
          when 0x12 then tune(0, (@frequencies[0] & 0xff) | ((value & 0x03) << 8))
          end
          @level = level_now
        end

        def frequency(voice) = @frequencies[voice]

        def reloading? = @reloading

        # A voice's square-wave output as of the current cycle, 1 high.
        def phase(voice)
          run_to(@clock.cycles)
          @phases[voice]
        end

        # The noise's shift register as of the current cycle.
        def noise
          run_to(@clock.cycles)
          @noise
        end

        # The output's level as of the current cycle.
        def level
          run_to(@clock.cycles)
          @level
        end

        private

        # Runs the voices up to the start of cycle `target`, the output holding
        # each level for the cycles it lasts.
        def run_to(target)
          time = @time
          return if target <= time

          output = @output
          return skip_to(target) if output.nil?

          following = next_toggle
          while following < target
            output.hold_level(@level, following - time)
            time = following
            toggle_due(time)
            @level = level_now
            following = next_toggle
          end
          output.hold_level(@level, target - time)
          @time = target
        end

        # Moves each voice through its toggles before `target` at once,
        # the noise by as many shifts as voice 2 toggles, less whole turns
        # of its sequence.
        def skip_to(target)
          VOICES.times do |voice|
            due = @next_toggles[voice]
            next if due >= target

            interval = @intervals[voice]
            toggles = ((target - 1 - due) / interval) + 1
            @next_toggles[voice] = due + (toggles * interval)
            @phases[voice] ^= toggles & 1
            next unless voice == 1

            (toggles % NOISE_PERIOD).times { shift_noise }
          end
          @level = level_now
          @time = target
        end

        def next_toggle
          toggles = @next_toggles
          following = toggles[0]
          following = toggles[1] if toggles[1] < following
          following
        end

        def toggle_due(time)
          toggles = @next_toggles
          VOICES.times do |voice|
            next unless toggles[voice] == time

            @phases[voice] ^= 1
            toggles[voice] = time + @intervals[voice]
            shift_noise if voice == 1
          end
        end

        def shift_noise
          noise = @noise
          taps = noise & NOISE_TAPS
          taps ^= taps >> 4
          taps ^= taps >> 2
          taps ^= taps >> 1
          @noise = ((noise << 1) | (taps & 1)) & 0xff
        end

        # The cycles between a voice's toggles at frequency `value`, and
        # never again after the next one at $3FE.
        def interval_for(value)
          return NEVER if value == HELD

          (((HELD - value) & 0x3ff) + 1) * CYCLES_PER_COUNT
        end

        # A new frequency for `voice`, which takes hold at its next toggle. A
        # voice stopped at $3FE starts counting now.
        def tune(voice, value)
          @frequencies[voice] = value
          @intervals[voice] = interval_for(value)
          return if @reloading || @next_toggles[voice] < NEVER

          @next_toggles[voice] = @time + @intervals[voice]
        end

        def write_control(value)
          reload = value >= 0x80
          if reload && !@reloading
            hold_voices
          elsif !reload && @reloading
            release_voices
          end
          @reloading = reload
          @control = value
          volume = value & 0x0f
          volume = 8 if volume > 8
          @volume = volume
        end

        def hold_voices
          @phases[0] = 1
          @phases[1] = 1
          @noise = 0xff
          @next_toggles[0] = NEVER
          @next_toggles[1] = NEVER
        end

        def release_voices
          VOICES.times { |voice| @next_toggles[voice] = @time + @intervals[voice] }
        end

        def level_now
          control = @control
          high = 0
          high += 1 if control.anybits?(0x10) && high?(0)
          if control.anybits?(0x20)
            high += 1 if high?(1)
          elsif control.anybits?(0x40) && !@reloading
            high += 1 if @noise.anybits?(0x02) || @frequencies[1] == HELD
          end
          LEVELS[(high * 9) + @volume]
        end

        def high?(voice) = @phases[voice] == 1 || @frequencies[voice] == HELD
      end
    end
  end
end
