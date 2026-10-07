# frozen_string_literal: true

require "badline/vic20/sound/output"

module Badline
  class Vic20
    # The VIC-I's sound: three square-wave voices, bass, alto and soprano at
    # $900A-$900C, a noise voice at $900D, and the volume in $900E bits 0-3.
    #
    # Each voice has a 7-bit counter, ticked every 16, 8, 4 or 2 cycles from
    # bass to noise. It counts up from the low 7 bits of its register, and
    # on the tick it would reach 127 it reloads from the register instead.
    # So a voice's counter comes round every 128 - ((value + 1) & 127)
    # ticks, and the register's new value takes hold at the next reload.
    #
    # A tone voice's counter shifts an 8-bit shift register at each reload,
    # bit 7 out and back into bit 0 inverted while bit 7 of the register
    # enables the voice, and a zero while it doesn't. Bit 0 is the voice's
    # output: a square wave of 16 shifts while the voice is on, which a
    # voice turned off shifts out to silence.
    #
    # The noise voice's counter shifts a 16-bit LFSR instead, bit 0 in from
    # the XOR of bits 3, 12, 14 and 15 while the voice is on and a one
    # while it's off. Each time the LFSR's bit 0 rises, it shifts the noise
    # voice's own 8-bit shift register, bit 7 back into bit 0, inverted
    # while the voice is on. Its bit 0 is the voice's output while the voice
    # is on, and it is silent while it's off.
    #
    # The output is the voices that are high, plus a little more, times the
    # volume, so a volume write steps the output even with every voice off.
    #
    # The voices only run while #record collects the output: nothing the
    # CPU reads depends on them. Until then a write only sets the register.
    # While recording, the voices catch up to the current cycle whenever a
    # write lands or the samples are drained, one shift at a time.
    class Sound
      VOICES = 4
      NOISE = 3

      # The cycles between ticks of each voice's counter.
      DIVIDERS = [16, 8, 4, 2].freeze

      # What a voice that is high adds to the output's level, and what the
      # output carries with every voice low, before the volume.
      VOICE_LEVEL = 9
      IDLE_LEVEL = 2

      attr_reader :volume

      # `clock` answers the machine's cycles, `clock_hz` the rate they run at.
      def initialize(clock, clock_hz)
        @clock = clock
        @clock_hz = clock_hz
        @output = nil
        @time = 0
        @shift_registers = Array.new(VOICES, 0)
        @next_shifts = Array.new(VOICES, 0)
        @frequencies = Array.new(VOICES, 0)
        @enabled = Array.new(VOICES, false)
        power_on!
      end

      def model = :mos6561

      # The power-on state: every register clear and the tone voices' shift
      # registers empty. The noise voice's LFSR and shift register start full
      # of ones, as a noise voice left off fills them.
      def power_on!
        now = @clock.cycles
        run_to(now)
        @volume = 0
        VOICES.times do |voice|
          @frequencies[voice] = 0
          @enabled[voice] = false
          @shift_registers[voice] = 0
          divider = DIVIDERS[voice]
          @next_shifts[voice] = ((now / divider) + 128) * divider
        end
        @shift_registers[NOISE] = 0xff
        @lfsr = 0xffff
        @level = level_now
      end

      # Starts collecting the output, averaged down to `rate` samples a
      # second, for #drain_samples. `clock_hz` is the rate the cycles are
      # taken to run at.
      def record(rate:, clock_hz: @clock_hz)
        now = @clock.cycles
        run_to(now)
        resume(now)
        @output = Output.new(clock_hz:, rate:, level: @level)
      end

      def recording? = !@output.nil?

      # The samples recorded since the last drain.
      def drain_samples
        output = @output
        return [] if output.nil?

        run_to(@clock.cycles)
        output.drain
      end

      # A write to $900A-$900E, which takes hold from the next cycle.
      def write(register, value)
        run_to(@clock.cycles + 1)
        if register == 0x0e
          @volume = value & 0x0f
        else
          voice = register - 0x0a
          @frequencies[voice] = value & 0x7f
          @enabled[voice] = value >= 0x80
        end
        @level = level_now
      end

      # The registers and the voices as they last ran, for a snapshot.
      # Recording is the host's, and starts the voices again from the
      # cycle it starts at.
      def save_state(out)
        run_to(@clock.cycles)
        out.marker("VIC20 SOUND").int(@volume).ints(@frequencies).booleans(@enabled)
        out.ints(@shift_registers).ints(@next_shifts).int(@lfsr).int(@level).int(@time)
      end

      def load_state(input)
        input.marker("VIC20 SOUND")
        @volume = input.int
        input.ints_into(@frequencies)
        input.booleans_into(@enabled)
        input.ints_into(@shift_registers)
        input.ints_into(@next_shifts)
        @lfsr = input.int
        @level = input.int
        @time = input.int
        resume(@clock.cycles) if recording?
      end

      # A voice's shift register as of the current cycle, while recording.
      def shift_register(voice)
        run_to(@clock.cycles)
        @shift_registers[voice]
      end

      def lfsr
        run_to(@clock.cycles)
        @lfsr
      end

      private

      # Moves each shift that the cycles since the voices last ran have
      # passed to its next turn from `now`, keeping its phase.
      def resume(now)
        @time = now
        VOICES.times do |voice|
          due = @next_shifts[voice]
          next if due >= now

          interval = period(voice) * DIVIDERS[voice]
          @next_shifts[voice] = due + ((now - due + interval - 1) / interval * interval)
        end
      end

      # Runs the voices up to the start of cycle `target`, the output holding
      # each level for the cycles it lasts.
      def run_to(target)
        time = @time
        output = @output
        return if output.nil? || target <= time

        following = next_shift
        while following < target
          output.hold(@level, following - time)
          time = following
          shift_due(time)
          @level = level_now
          following = next_shift
        end
        output.hold(@level, target - time)
        @time = target
      end

      def next_shift
        shifts = @next_shifts
        following = shifts[0]
        following = shifts[1] if shifts[1] < following
        following = shifts[2] if shifts[2] < following
        following = shifts[3] if shifts[3] < following
        following
      end

      def shift_due(time)
        shifts = @next_shifts
        VOICES.times do |voice|
          next unless shifts[voice] == time

          voice == NOISE ? step_noise : shift_tone(voice)
          shifts[voice] = time + (period(voice) * DIVIDERS[voice])
        end
      end

      def shift_tone(voice)
        bits = @shift_registers[voice]
        fill = @enabled[voice] && bits < 0x80 ? 1 : 0
        @shift_registers[voice] = ((bits << 1) | fill) & 0xff
      end

      def step_noise
        lfsr = @lfsr
        enabled = @enabled[NOISE]
        fill = enabled ? ((lfsr >> 3) ^ (lfsr >> 12) ^ (lfsr >> 14) ^ (lfsr >> 15)) & 1 : 1
        @lfsr = ((lfsr << 1) | fill) & 0xffff
        return unless fill == 1 && lfsr.even?

        bits = @shift_registers[NOISE]
        fill = (bits >> 7) ^ (enabled ? 1 : 0)
        @shift_registers[NOISE] = ((bits << 1) | fill) & 0xff
      end

      # The ticks between two reloads of a voice's counter.
      def period(voice) = 128 - ((@frequencies[voice] + 1) & 0x7f)

      def level_now
        registers = @shift_registers
        high = (registers[0] & 1) + (registers[1] & 1) + (registers[2] & 1)
        high += registers[NOISE] & 1 if @enabled[NOISE]
        ((high * VOICE_LEVEL) + IDLE_LEVEL) * @volume
      end
    end
  end
end
