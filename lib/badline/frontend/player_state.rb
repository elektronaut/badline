# frozen_string_literal: true

module Badline
  module Frontend
    # What the SID player's window shows about playback: the subtune and the
    # tune's place in the queue, the time, the modes the jukebox reports
    # as notes, the view and SID model chosen, which of a tune's SIDs the
    # SID view shows, and where a seek is headed until playback gets there.
    class PlayerState
      attr_accessor :subtune, :subtunes, :tune, :tunes, :length, :notes, :view, :chip, :sid
      attr_reader :target

      def initialize
        @subtune = 0
        @subtunes = 0
        @tune = 0
        @tunes = 0
        @length = 0.0
        @notes = []
        @view = 0
        @chip = 0
        @sid = 0
        @elapsed = 0.0
        @elapsed_at = now
        @target = 0.0
        @below = false
      end

      # The seconds heard as the jukebox last reported them.
      def elapsed=(seconds)
        @elapsed = seconds
        @elapsed_at = now
        return unless seeking?

        @below ||= seconds < @target
        stop_seeking if @below && seconds >= @target
      end

      # Notes a seek to `seconds`, which lasts until playback has come up
      # to it from below.
      def seek(seconds)
        @target = seconds
        @below = false
      end

      def stop_seeking = @target = 0.0

      def seeking? = @target.positive?

      # The seconds heard so far: the last reported, carried on by the
      # clock unless it is paused.
      def played
        return @elapsed if paused?

        [@elapsed + (now - @elapsed_at), @length].min
      end

      def paused? = on?("paused")

      def on?(note) = @notes.include?(note)

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
