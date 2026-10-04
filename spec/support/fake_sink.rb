# frozen_string_literal: true

# An audio device on a simulated clock: once started it plays `rate`
# stereo samples a second of simulated time, each a left and a right
# value queued in turn, and time only passes through
# #advance, which a Playback's sleeper and a FakeRenderer both call. An
# `instant` one plays whatever it holds as soon as it has started.
class FakeSink
  attr_accessor :requested
  attr_reader :rate, :queued, :played, :peak, :started_with, :cleared, :closed_with

  def initialize(rate: 1000, instant: false)
    @rate = rate
    @instant = instant
    @queued = 0
    @played = 0
    @total = 0
    @peak = 0
    @closed_with = nil
    @cleared = false
    @running = false
  end

  def queue(samples)
    @queued += samples.length / 2
    @total += samples.length / 2
    @peak = [@peak, @queued].max
    play_out if @instant
  end

  def queued_seconds = @queued.fdiv(rate)

  def start
    @started_with = @queued unless started?
    @running = true
    play_out if @instant
  end

  def pause = @running = false

  def started? = !@started_with.nil?

  def running? = @running

  def clear
    @queued = 0
    @cleared = true
  end

  def close = @closed_with = @queued

  def closed? = !@closed_with.nil?

  def total_seconds = @total.fdiv(rate)

  def advance(seconds)
    return unless running?

    consumed = [(seconds * rate).ceil, @queued].min
    @queued -= consumed
    @played += consumed
  end

  def play_out = advance(queued_seconds)
end

# Stands in for Renderer#stream: `frames` frames of `size` stereo samples, each
# taking `cost` seconds of the sink's simulated time to render. The frames
# before `from` seconds come without their samples. With `ahead` set, a
# checkpoint lies ahead of where it plays, short of any seek forward.
class FakeRenderer
  attr_reader :rendered
  attr_accessor :from, :checkpoints
  attr_writer :ahead

  def initialize(sink, frames:, size:, cost: 0.0)
    @sink = sink
    @frames = frames
    @size = size
    @cost = cost
    @rendered = 0
    @from = 0.0
    @ahead = false
  end

  def checkpoint_ahead?(_seconds) = @ahead

  def stream
    @frames.times do
      @sink.advance(@cost)
      @rendered += 1
      seconds = (@rendered * @size).fdiv(@sink.rate)
      yield(seconds <= @from ? [] : Array.new(@size * 2, 0), seconds)
    end
  end
end
