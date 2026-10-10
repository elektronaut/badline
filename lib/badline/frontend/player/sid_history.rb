# frozen_string_literal: true

module Badline
  module Frontend
    # Each SID's state at the end of each frame rendered, and the samples
    # rendered, kept for long enough that the SID player can show what is
    # being heard rather than what was last rendered: rendering runs ahead
    # of the audio device by the queue in between.
    #
    # The samples come in four channels a SID, 0 to 3 for SID 1, 4 to 7 for
    # SID 2 and so on: each voice's own output, when the SID records them,
    # then the SID's own output (#output). The left and right of the mix
    # follow them all (#left and #right).
    class SIDHistory
      FRAMES = 64
      SAMPLES = 16_384

      # Per frame: the 25 write registers, then each voice's envelope level,
      # then each voice's envelope state as an index into STATES.
      FIELDS = 31
      LEVELS = 25
      PHASES = 28

      STATES = %i[attack decay_sustain release].freeze

      # SID 1's own output, which is the mix with only one SID.
      MIX = 3

      attr_reader :rate, :sid_count

      def initialize(rate, sid_count = 1)
        @rate = rate
        @sid_count = sid_count
        @channels = (sid_count * 4) + 2
        @times = Array.new(FRAMES, 0.0)
        @states = Array.new(FRAMES * FIELDS * sid_count, 0)
        @frames = 0
        @samples = Array.new(SAMPLES * @channels, 0)
        @written = 0
        @rendered = 0.0
      end

      # Keeps the frame that ends at `rendered` seconds: the state of each of
      # `sids`, each one's own samples in `outputs`, and the stereo mix in
      # `samples`, the left and right interleaved.
      def record(sids, outputs, samples, rendered)
        slot = @frames % FRAMES
        @times[slot] = rendered
        sids.size.times { |index| keep_state(sids[index], ((slot * @sid_count) + index) * FIELDS) }
        @frames += 1
        keep(sids, outputs, samples)
        @rendered = rendered
      end

      def empty? = @frames.zero?

      def output(sid) = (sid * 4) + MIX

      def left = @sid_count * 4

      def right = left + 1

      # Where the fields of SID `sid` in the frame heard at `played` seconds
      # start: the latest frame rendered by then, or the oldest kept.
      def frame(played, sid = 0)
        kept = [@frames, FRAMES].min
        newest = @frames - 1
        age = 0
        while age < kept - 1
          break if @times[(newest - age) % FRAMES] <= played

          age += 1
        end
        ((((newest - age) % FRAMES) * @sid_count) + sid) * FIELDS
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

      def sample_at(index, channel = MIX) = @samples[((index % SAMPLES) * @channels) + channel]

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

      def keep_state(sid, base)
        states = @states
        25.times { |reg| states[base + reg] = sid.register(reg) }
        voices = sid.voices
        3.times do |voice|
          envelope = voices[voice].envelope
          states[base + LEVELS + voice] = envelope.counter
          states[base + PHASES + voice] = STATES.index(envelope.state) || 0
        end
      end

      def keep(sids, outputs, samples)
        first = @written
        sids.size.times { |index| keep_sid(first, index * 4, outputs[index], sids[index].drain_voice_samples) }
        stored = @samples
        channels = @channels
        left = channels - 2
        i = 0
        while (i * 2) + 1 < samples.size
          slot = ((@written % SAMPLES) * channels) + left
          stored[slot] = samples[i * 2]
          stored[slot + 1] = samples[(i * 2) + 1]
          @written += 1
          i += 1
        end
      end

      def keep_sid(first, channel, output, voices)
        stored = @samples
        channels = @channels
        i = 0
        while i < output.size
          slot = (((first + i) % SAMPLES) * channels) + channel
          stored[slot + MIX] = output[i]
          if voices.size > (i * 3) + 2
            stored[slot] = voices[i * 3]
            stored[slot + 1] = voices[(i * 3) + 1]
            stored[slot + 2] = voices[(i * 3) + 2]
          end
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
