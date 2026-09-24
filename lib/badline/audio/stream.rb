# frozen_string_literal: true

module Badline
  module Audio
    # Plays a running machine's SID through a sink, for the window: #feed
    # queues whatever the SID recorded since the last call, once a frame,
    # and #pace holds the machine to the device's clock.
    #
    # The device starts once the queue holds `ahead` seconds. Below real time
    # the queue runs dry, and the device then stops until it holds `ahead`
    # again, so the sound stutters with silent gaps rather than slowing
    # down; `on_underrun` hears about the first time. A frame that would
    # take the queue past `limit` seconds, as an unpaced machine above real
    # time makes, is dropped whole.
    class Stream
      AHEAD = 0.08
      LIMIT = 0.25

      attr_reader :underruns, :dropped

      # What #pace reads the time from and sleeps on: #now and #sleep.
      attr_writer :clock

      def initialize(sink, sid, ahead: AHEAD, limit: LIMIT, on_underrun: nil)
        @sink = sink
        @sid = sid
        @ahead = ahead
        @limit = limit
        @on_underrun = on_underrun
        @clock = Clock.new
        @next_frame = nil
        @started = false
        @muted = false
        @underruns = 0
        @dropped = 0
        sid.record(rate: sink.rate)
      end

      def rate = @sink.rate

      def muted? = @muted

      def playing? = @started

      # Muting drops the queue; unmuting fills it to `ahead` again before
      # the device restarts.
      def toggle_mute
        @muted = !@muted
        return unless @muted

        halt
        @sink.clear
      end

      def feed
        samples = @sid.drain_samples
        return if @muted || samples.empty?

        queued = @sink.queued_seconds
        return @dropped += samples.size if queued + samples.size.fdiv(rate) > @limit

        underrun! if @started && queued.zero?
        @sink.queue(samples)
        start if @sink.queued_seconds >= @ahead
      end

      # Waits out the frame just run. While the device plays, that is until
      # it has played the queue down to `ahead`, so the machine runs at the
      # device's rate and the queue neither drifts dry nor grows. Muted or
      # filling up, the clock paces frames `seconds` apart instead.
      def pace(seconds)
        return wait_for_device if playing?

        now = @clock.now
        @next_frame = now if @next_frame.nil? || @next_frame < now
        @clock.sleep(@next_frame - now)
        @next_frame += seconds
      end

      def close = @sink.close

      private

      def start
        return if @started

        @started = true
        @sink.start
      end

      def wait_for_device
        @next_frame = nil
        while (excess = @sink.queued_seconds - @ahead).positive?
          @clock.sleep([excess, 0.001].max)
        end
      end

      def halt
        @started = false
        @sink.pause
      end

      def underrun!
        @underruns += 1
        @on_underrun&.call if @underruns == 1
        halt
      end

      # The host's monotonic clock.
      class Clock
        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        def sleep(seconds) = Kernel.sleep(seconds)
      end
    end
  end
end
