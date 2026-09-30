# frozen_string_literal: true

module Badline
  module Audio
    # Plays a Media::Queue of tunes interactively: the console's keys step
    # through the queue, pause, turn its shuffle, loop and all-songs modes
    # on and off, and quit, and the status line follows along. A song that
    # plays to its end moves on to the queue's next one. It stops at the
    # end of the queue, on q, or on Ctrl-C.
    #
    # `renderer` builds the renderer for an entry's song at the sink's
    # rate, and `length` gives an entry's song's length in seconds.
    class Jukebox
      def initialize(sink, console, queue:, renderer:, length:)
        @sink = sink
        @console = console
        @queue = queue
        @renderer = renderer
        @length = length
        @below = false
      end

      # Returns the result of the last song's Playback#play.
      def run
        loop do
          @moved = false
          @quit = false
          result = play(@queue.entry, @queue.part)
          return result if @quit
          next if @moved
          return result unless result == :finished && @queue.forward
        end
      end

      private

      def play(entry, song)
        @entry = entry
        @song = song
        @elapsed = 0.0
        @playback = Playback.new(@sink, sleeper: ->(seconds) { react(@console.wait(seconds)) },
                                        on_underrun: -> { @below = true })
        draw
        @playback.play(@renderer.call(entry, song, @sink.rate)) do |played|
          @elapsed = played
          react(@console.wait(0))
          draw
        end
      end

      def react(actions)
        actions.each do |action|
          case action
          when :pause then toggle_pause
          when :next then skip if @queue.forward
          when :previous then skip if @queue.back
          when :shuffle then @queue.toggle_shuffle
          when :loop then @queue.toggle_loop
          when :all_songs then @queue.toggle_all_parts
          when :quit then quit
          end
        end
        draw unless actions.empty?
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
        @console.status(song: @song, songs: @entry.parts, elapsed: @elapsed, length: @length.call(@entry, @song),
                        notes:)
      end

      def notes
        notes = []
        notes << "paused" if @playback.paused?
        notes << "shuffle" if @queue.shuffle?
        notes << "loop" if @queue.loop?
        notes << "all songs" if @queue.all_parts?
        notes << "below real time" if @below
        notes
      end
    end
  end
end
