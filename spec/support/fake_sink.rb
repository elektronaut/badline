# frozen_string_literal: true

# An audio device on a simulated clock: once started it plays `rate`
# samples a second of simulated time, and time only passes through
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
  end

  def queue(samples)
    @queued += samples.length
    @total += samples.length
    @peak = [@peak, @queued].max
    play_out if @instant
  end

  def queued_seconds = @queued.fdiv(rate)

  def start
    @started_with = @queued unless started?
    play_out if @instant
  end

  def started? = !@started_with.nil?

  def clear
    @queued = 0
    @cleared = true
  end

  def close = @closed_with = @queued

  def closed? = !@closed_with.nil?

  def total_seconds = @total.fdiv(rate)

  def advance(seconds)
    return unless started?

    consumed = [(seconds * rate).ceil, @queued].min
    @queued -= consumed
    @played += consumed
  end

  def play_out = advance(queued_seconds)
end

# Stands in for Renderer#stream: `frames` frames of `size` samples, each
# taking `cost` seconds of the sink's simulated time to render.
class FakeRenderer
  attr_reader :rendered

  def initialize(sink, frames:, size:, cost: 0.0)
    @sink = sink
    @frames = frames
    @size = size
    @cost = cost
    @rendered = 0
  end

  def stream
    @frames.times do
      @sink.advance(@cost)
      @rendered += 1
      yield Array.new(@size, 0), (@rendered * @size).fdiv(@sink.rate)
    end
  end
end
