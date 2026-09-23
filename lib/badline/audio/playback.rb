# frozen_string_literal: true

module Badline
  module Audio
    # Plays a renderer's frames through a sink in real time. The queue is
    # kept a little ahead of the device: a frame is only rendered once the
    # queue has drained below `ahead` seconds, and the device only starts
    # once the queue first reaches it.
    #
    # A sink answers #rate, #queue(samples), #queued_seconds, #start, #clear
    # and #close. An emulator running below real time lets the queue run dry
    # and the audio stutters; `on_underrun` hears about the first time.
    class Playback
      AHEAD = 0.15

      def initialize(sink, ahead: AHEAD, sleeper: ->(seconds) { sleep(seconds) }, on_underrun: nil)
        @sink = sink
        @ahead = ahead
        @sleeper = sleeper
        @on_underrun = on_underrun
        @started = false
        @stopped = false
        @underrun = false
      end

      def stopped? = @stopped

      def underrun? = @underrun

      # Stops at the end of the next wait; the queue is dropped rather than
      # played out.
      def stop = @stopped = true

      # Plays to the end of the renderer and waits for the device to finish,
      # yielding the seconds played so far after each frame. Returns
      # :finished, :stopped, or :interrupted after a Ctrl-C.
      def play(renderer)
        renderer.stream do |samples, rendered|
          break if @stopped

          enqueue(samples)
          yield [rendered - @sink.queued_seconds, 0.0].max if block_given?
        end
        drain
        @stopped ? :stopped : :finished
      rescue Interrupt
        @stopped = true
        :interrupted
      ensure
        @sink.clear if @stopped
        @sink.close
      end

      private

      def enqueue(samples)
        wait_below(@ahead)
        underrun! if @started && @sink.queued_seconds.zero?
        @sink.queue(samples)
        start if @sink.queued_seconds >= @ahead
      end

      def drain
        start
        wait_below(1.fdiv(@sink.rate))
      end

      def start
        return if @started

        @sink.start
        @started = true
      end

      def underrun!
        return if @underrun

        @underrun = true
        @on_underrun&.call
      end

      def wait_below(level)
        until @stopped
          excess = @sink.queued_seconds - level
          break if excess.negative?

          @sleeper.call([excess, 0.001].max)
        end
      end
    end
  end
end
