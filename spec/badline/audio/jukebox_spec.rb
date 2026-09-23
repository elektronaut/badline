# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/fake_sink"

# Hands out one scripted batch of actions per wait and lets the sink's
# simulated clock run for the time waited.
class ScriptedConsole
  attr_reader :statuses

  def initialize(sink, script)
    @sink = sink
    @script = script
    @waits = 0
    @statuses = []
  end

  def wait(seconds)
    @sink.advance(seconds)
    @waits += 1
    @script.fetch(@waits, [])
  end

  def status(**fields) = @statuses << fields
end

describe Badline::Audio::Jukebox do
  subject(:jukebox) do
    described_class.new(sink, console, songs: 3, renderer:, length: ->(song) { song * 10.0 })
  end

  let(:sink) { FakeSink.new(rate: 1000) }
  let(:console) { ScriptedConsole.new(sink, script) }
  let(:script) { {} }
  let(:played) { [] }
  let(:renderer) do
    lambda do |song, _rate|
      played << song
      FakeRenderer.new(sink, frames: 20, size: 20)
    end
  end

  it "plays the song it starts on to the end" do
    jukebox.run(2)
    expect([played, sink.played]).to eq([[2], 400])
  end

  it "reports how the song ended" do
    expect(jukebox.run(2)).to eq(:finished)
  end

  it "shows the song, its number and its length" do
    jukebox.run(2)
    expect(console.statuses.last).to include(song: 2, songs: 3, length: 20.0)
  end

  context "with n pressed" do
    let(:script) { { 3 => [:next] } }

    it "moves on to the next song" do
      jukebox.run(2)
      expect(played).to eq([2, 3])
    end
  end

  context "with n pressed on the last song" do
    let(:script) { { 3 => [:next] } }

    it "stays on it" do
      jukebox.run(3)
      expect(played).to eq([3])
    end
  end

  context "with p pressed" do
    let(:script) { { 3 => [:previous] } }

    it "goes back a song" do
      jukebox.run(2)
      expect(played).to eq([2, 1])
    end
  end

  context "with p pressed on the first song" do
    let(:script) { { 3 => [:previous] } }

    it "stays on it" do
      jukebox.run(1)
      expect(played).to eq([1])
    end
  end

  context "with q pressed" do
    let(:script) { { 3 => [:quit] } }

    it "stops" do
      expect(jukebox.run(2)).to eq(:stopped)
    end

    it "plays no further song" do
      jukebox.run(2)
      expect(played).to eq([2])
    end
  end

  context "with space pressed twice" do
    let(:script) { { 3 => [:pause], 8 => [:pause] } }

    it "shows the pause while it lasts" do
      jukebox.run(2)
      paused = console.statuses.map { |status| status[:notes].include?("paused") }
      expect(paused.chunk_while(&:==).map(&:first)).to eq([false, true, false])
    end

    it "then plays the song out" do
      jukebox.run(2)
      expect(sink.played).to eq(400)
    end
  end

  context "when the tune can't keep up" do
    let(:renderer) { ->(_song, _rate) { FakeRenderer.new(sink, frames: 20, size: 20, cost: 0.04) } }

    it "says so on the status line" do
      jukebox.run(2)
      expect(console.statuses.last[:notes]).to include("below real time")
    end
  end
end
