# frozen_string_literal: true

module Badline
  module Frontend
    # The --verbose report every 50 frames: the frame rate, the time each
    # stage of a frame took on average, the slowest frame's work, and how
    # the sound's queue fared.
    class FrameReport
      STAGES = %w[events emulate audio blit present wait].freeze

      def initialize(sound)
        @sound = sound
        @reported_samples = 0
        clear
      end

      # Adds a frame's stamps, one as each stage starts and one after the
      # last.
      def add(stamps)
        STAGES.size.times { |stage| @spent[stage] += stamps[stage + 1] - stamps[stage] }
        took = stamps[-2] - stamps.first
        @slowest = took if took > @slowest
      end

      # Reports the 50 frames added over the last `seconds`, and starts
      # over.
      def show(seconds)
        stages = STAGES.each_with_index.map { |name, stage| "#{name} #{(@spent[stage] * 20).round(2)}" }
        puts "#{(50 / seconds).round(1)} fps, per frame ms: #{stages.join(' ')}, " \
             "slowest work #{(@slowest * 1000).round(2)}"
        show_sound(seconds) if @sound.on?
        clear
      end

      private

      def clear
        @spent = Array.new(STAGES.size, 0.0)
        @slowest = 0.0
      end

      def show_sound(seconds)
        sound = @sound
        rate = (sound.queued - @reported_samples) / seconds
        queue = sound.high.zero? ? "empty" : "#{(sound.low * 1000).round(1)}-#{(sound.high * 1000).round(1)} ms"
        puts "  sound #{rate.round} samples/s, queue #{queue}, #{sound.underruns} underruns, #{sound.dropped} dropped"
        sound.reset_levels
        @reported_samples = sound.queued
      end
    end
  end
end
