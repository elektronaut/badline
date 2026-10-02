# frozen_string_literal: true

module Badline
  module Frontend
    # What the SID player's window shows about playback: the subtune and the
    # tune's place in the queue, the time, the modes the jukebox reports
    # as notes, the view and SID model chosen, and which of a tune's SIDs
    # the SID view shows.
    class PlayerState
      attr_accessor :subtune, :subtunes, :tune, :tunes, :length, :notes, :view, :chip, :sid

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
      end

      # The seconds heard as the jukebox last reported them.
      def elapsed=(seconds)
        @elapsed = seconds
        @elapsed_at = now
      end

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
