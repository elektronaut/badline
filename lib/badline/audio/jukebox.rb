# frozen_string_literal: true

module Badline
  module Audio
    # Plays a Media::Queue of tunes interactively: the console's keys step
    # between tunes and between a tune's subtunes, seek within the subtune, pause,
    # turn the queue's shuffle, loop and all-subtunes modes on and off, and
    # quit, and the status line follows along. Seeking plays the subtune again
    # from the start, running silently up to where it was asked to go. A subtune that plays to its end moves on as
    # Media::Queue#advance says. It stops at the end of the queue, on q, or
    # on Ctrl-C.
    #
    # `renderer` builds the renderer for an entry's subtune at the sink's
    # rate, or returns nil for an entry that can't play, which is skipped
    # in the direction the queue was stepping. `length` gives an entry's
    # subtune's length in seconds.
    class Jukebox
      SEEK_STEP = 10.0

      # How long the status line says the player fell below real time after
      # the last time it did.
      BELOW_NOTE = 3.0

      def initialize(sink, console, queue:, renderer:, length:)
        @sink = sink
        @console = console
        @queue = queue
        @renderer = renderer
        @length = length
        @backward = false
        @below_at = -BELOW_NOTE
        @from = 0.0
      end

      # Returns the result of the last subtune's Playback#play, or :unplayable
      # when the last entry reached couldn't play.
      def run
        skipped = 0
        loop do
          @moved = false
          @quit = false
          result = play(@queue.entry, @queue.part)
          return result if @quit
          next if @moved

          skipped = result == :unplayable ? skipped + 1 : 0
          return result if skipped >= @queue.size || !move_on(result)
        end
      end

      private

      def move_on(result)
        return @queue.advance if result == :finished
        return false unless result == :unplayable
        return @queue.advance unless @backward

        @queue.previous_entry || @queue.advance
      end

      def play(entry, subtune)
        @entry = entry
        @subtune = subtune
        @elapsed = 0.0
        renderer = @renderer.call(entry, subtune, @sink.rate)
        return :unplayable if renderer.nil?

        renderer.from = @from
        @from = 0.0
        @backward = false
        @playback = Playback.new(@sink, sleeper: ->(seconds) { react(@console.wait(seconds)) },
                                        on_underrun: -> { @below_at = now })
        draw
        @playback.play(renderer) do |played|
          @elapsed = played
          react(@console.wait(0))
          draw unless @moved
        end
      end

      def react(actions)
        actions.each do |action|
          case action
          when :pause then toggle_pause
          when :shuffle then @queue.toggle_shuffle
          when :loop then @queue.toggle_loop
          when :all_subtunes then @queue.toggle_all_parts
          when :quit then quit
          when :seek then seek(@console.seek_to)
          when :forward then seek(@elapsed + SEEK_STEP)
          when :back then seek(@elapsed - SEEK_STEP)
          else skip if step(action)
          end
        end
        draw unless actions.empty? || @moved
      end

      def step(action)
        @backward = action == :previous if %i[next previous].include?(action)
        case action
        when :next then @queue.next_entry
        when :previous then @queue.previous_entry
        when :next_subtune then @queue.next_part
        when :previous_subtune then @queue.previous_part
        end
      end

      def seek(seconds)
        @from = seconds.clamp(0.0, [@length.call(@entry, @subtune) - 1.0, 0.0].max)
        skip
      end

      def skip
        @moved = true
        @playback.stop
      end

      def quit
        @quit = true
        @playback.stop
      end

      def toggle_pause
        @playback.paused? ? @playback.resume : @playback.pause
      end

      def draw
        @console.place(@queue.position, @queue.size)
        @console.status(subtune: @subtune, subtunes: @entry.parts, elapsed: @elapsed,
                        length: @length.call(@entry, @subtune), notes:)
      end

      def notes
        notes = []
        notes << "paused" if @playback.paused?
        notes << "shuffle" if @queue.shuffle?
        notes << "loop" if @queue.loop?
        notes << "all subtunes" if @queue.all_parts?
        notes << "below real time" if now - @below_at < BELOW_NOTE
        notes
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
