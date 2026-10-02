# frozen_string_literal: true

module Badline
  module Frontend
    # The SID's state at the end of each frame rendered, and the samples
    # rendered, kept for long enough that the SID player can show what is
    # being heard rather than what was last rendered: rendering runs ahead
    # of the audio device by the queue in between.
    #
    # The samples come in four channels: the mix, MIX, and each voice's own
    # output, 0 to 2, when the SID records them.
    class SIDHistory
      FRAMES = 64
      SAMPLES = 16_384

      # Per frame: the 25 write registers, then each voice's envelope level,
      # then each voice's envelope state as an index into STATES.
      FIELDS = 31
      LEVELS = 25
      PHASES = 28

      STATES = %i[attack decay_sustain release].freeze

      MIX = 3

      attr_reader :rate

      def initialize(rate)
        @rate = rate
        @times = Array.new(FRAMES, 0.0)
        @states = Array.new(FRAMES * FIELDS, 0)
        @frames = 0
        @samples = Array.new(SAMPLES * 4, 0)
        @written = 0
        @rendered = 0.0
      end

      def record(sid, samples, rendered)
        base = (@frames % FRAMES) * FIELDS
        @times[@frames % FRAMES] = rendered
        25.times { |reg| @states[base + reg] = sid.register(reg) }
        voices = sid.voices
        3.times do |voice|
          envelope = voices[voice].envelope
          @states[base + LEVELS + voice] = envelope.counter
          @states[base + PHASES + voice] = STATES.index(envelope.state) || 0
        end
        @frames += 1
        keep(samples, sid.drain_voice_samples)
        @rendered = rendered
      end

      def empty? = @frames.zero?

      # Where the fields of the frame heard at `played` seconds start: the
      # latest frame rendered by then, or the oldest kept.
      def frame(played)
        kept = [@frames, FRAMES].min
        newest = @frames - 1
        age = 0
        while age < kept - 1
          break if @times[(newest - age) % FRAMES] <= played

          age += 1
        end
        ((newest - age) % FRAMES) * FIELDS
      end

      def register(frame, reg) = @states[frame + reg]

      # The voice's oscillator frequency in hertz, at the SID's clock.
      def hertz(frame, voice, clock_hz)
        base = voice * 7
        (register(frame, base) | (register(frame, base + 1) << 8)) * clock_hz / 16_777_216.0
      end

      def level(frame, voice) = @states[frame + LEVELS + voice]

      def state(frame, voice) = STATES[@states[frame + PHASES + voice]]

      # The first of `count` samples of `channel` heard up to `played`
      # seconds, moved back to where the wave last rose through its middle,
      # so a steady tone holds still from one frame to the next.
      def scope_start(played, count, channel = MIX)
        last = @written - ((@rendered - played) * @rate).round
        last = @written if last > @written
        earliest = [@written - SAMPLES, 0].max
        start = last - count
        return earliest if start < earliest

        rising(start, [start - count, earliest].max, channel)
      end

      def sample_at(index, channel = MIX) = @samples[((index % SAMPLES) * 4) + channel]

      # The middle of the range `channel` covers over `count` samples from
      # `start`, which a voice's scope centres on.
      def middle(start, count, channel)
        low = high = sample_at(start, channel)
        index = start + 1
        while index < start + count
          value = sample_at(index, channel)
          low = value if value < low
          high = value if value > high
          index += 1
        end
        (low + high) / 2
      end

      private

      def keep(samples, voices)
        stored = @samples
        i = 0
        while i < samples.size
          slot = (@written % SAMPLES) * 4
          stored[slot + MIX] = samples[i]
          if voices.size > (i * 3) + 2
            stored[slot] = voices[i * 3]
            stored[slot + 1] = voices[(i * 3) + 1]
            stored[slot + 2] = voices[(i * 3) + 2]
          end
          @written += 1
          i += 1
        end
      end

      def rising(start, limit, channel)
        middle = middle(limit, start - limit + 1, channel)
        index = start
        while index > limit
          return index if sample_at(index - 1, channel) < middle && sample_at(index, channel) >= middle

          index -= 1
        end
        start
      end
    end
  end
end
