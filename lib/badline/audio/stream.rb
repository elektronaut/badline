# frozen_string_literal: true

module Badline
  module Audio
    # Plays a running machine's SID through a sink, for the window. The
    # emulator keeps its own pace and the audio follows: #feed queues
    # whatever the SID recorded since the last call, once a frame.
    #
    # The device starts once the queue holds `ahead` seconds. Below real time
    # the queue runs dry, and the device then stops until it holds `ahead`
    # again, so the sound stutters with silent gaps rather than slowing
    # down; `on_underrun` hears about the first time. Above real time a
    # frame that would take the queue past `limit` seconds is dropped whole.
    class Stream
      AHEAD = 0.08
      LIMIT = 0.25

      attr_reader :underruns, :dropped

      def initialize(sink, sid, ahead: AHEAD, limit: LIMIT, on_underrun: nil)
        @sink = sink
        @sid = sid
        @ahead = ahead
        @limit = limit
        @on_underrun = on_underrun
        @started = false
        @muted = false
        @underruns = 0
        @dropped = 0
        sid.record(rate: sink.rate)
      end

      def rate = @sink.rate

      def muted? = @muted

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

      def close = @sink.close

      private

      def start
        return if @started

        @started = true
        @sink.start
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
    end
  end
end
