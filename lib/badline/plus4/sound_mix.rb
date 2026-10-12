# frozen_string_literal: true

module Badline
  class Plus4
    # What a front end plays from a 264 with a SID card fitted: the TED's
    # sound and the card's SID, each recorded at the audio rate and added
    # together, clipped to a signed 16-bit sample. A sample one source has
    # closed waits for the other's. The SID's model is the mix's, as it
    # is a C64's sound source's, for the pause menu's Sound page.
    class SoundMix
      def initialize(ted_sound, sid)
        @ted_sound = ted_sound
        @sid = sid
        @ted_waiting = []
        @sid_waiting = []
      end

      def model = @sid.model

      def model=(model)
        @sid.model = model
      end

      # Starts both sources recording at `rate` samples a second, their
      # cycles taken to run at `clock_hz`.
      def record(rate:, clock_hz:)
        @ted_sound.record(rate:, clock_hz:)
        @sid.record(rate:, clock_hz:)
        @ted_waiting = []
        @sid_waiting = []
      end

      # Runs both sources up to the current cycle.
      def catch_up!
        @ted_sound.catch_up!
        @sid.catch_up!
      end

      # The mixed samples both sources have closed since the last drain.
      def drain_samples
        ted = @ted_waiting.concat(@ted_sound.drain_samples)
        sid = @sid_waiting.concat(@sid.drain_samples)
        count = [ted.length, sid.length].min
        mixed = Array.new(count) { |index| (ted[index] + sid[index]).clamp(-0x8000, 0x7fff) }
        @ted_waiting = ted[count, ted.length - count] || []
        @sid_waiting = sid[count, sid.length - count] || []
        mixed
      end
    end
  end
end
