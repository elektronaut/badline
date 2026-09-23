# frozen_string_literal: true

module Badline
  module Audio
    # Plays a tune's songs interactively: the console's keys step between
    # songs, pause and quit, and the status line follows along. It stops
    # when a song ends, on q, or on Ctrl-C.
    #
    # `renderer` builds the renderer for a song at the sink's rate, and
    # `length` gives a song's length in seconds.
    class Jukebox
      def initialize(sink, console, songs:, renderer:, length:)
        @sink = sink
        @console = console
        @songs = songs
        @renderer = renderer
        @length = length
        @below = false
      end

      # Returns the result of the last song's Playback#play.
      def run(song)
        loop do
          @action = nil
          result = play(song)
          song = following(song)
          return result unless song
        end
      end

      private

      def play(song)
        @song = song
        @elapsed = 0.0
        @playback = Playback.new(@sink, sleeper: ->(seconds) { react(@console.wait(seconds)) },
                                        on_underrun: -> { @below = true })
        draw
        @playback.play(@renderer.call(song, @sink.rate)) do |played|
          @elapsed = played
          react(@console.wait(0))
          draw
        end
      end

      def following(song)
        case @action
        when :next then song + 1
        when :previous then song - 1
        end
      end

      def react(actions)
        actions.each do |action|
          case action
          when :pause then toggle_pause
          when :next then skip(:next) if @song < @songs
          when :previous then skip(:previous) if @song > 1
          when :quit then skip(:quit)
          end
        end
      end

      def skip(action)
        @action = action
        @playback.stop
      end

      def toggle_pause
        @playback.paused? ? @playback.resume : @playback.pause
        draw
      end

      def draw
        notes = []
        notes << "paused" if @playback.paused?
        notes << "below real time" if @below
        @console.status(song: @song, songs: @songs, elapsed: @elapsed, length: @length.call(@song), notes:)
      end
    end
  end
end
