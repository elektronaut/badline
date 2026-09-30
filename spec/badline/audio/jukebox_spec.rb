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

# A renderer interrupted by Ctrl-C as it starts.
class InterruptingRenderer
  def stream = raise(Interrupt)
end

describe Badline::Audio::Jukebox do
  subject(:jukebox) do
    described_class.new(sink, console, queue:, renderer:, length: ->(_entry, song) { song * 10.0 })
  end

  let(:sink) { FakeSink.new(rate: 1000) }
  let(:console) { ScriptedConsole.new(sink, script) }
  let(:script) { {} }
  let(:queue) { tune(1) }
  let(:renderer) do
    lambda do |_entry, song, _rate|
      played << song
      FakeRenderer.new(sink, frames: 20, size: 20)
    end
  end

  def played = @played ||= []

  def tune(start, all_songs: false)
    Badline::Media::Queue.new([Badline::Media::Queue::Entry.new("tune.sid", part: start, parts: 3)],
                              all_parts: all_songs)
  end

  def tunes(*songs, all_songs: false)
    entries = songs.map { |parts| Badline::Media::Queue::Entry.new("#{parts}.sid", parts:) }
    Badline::Media::Queue.new(entries, all_parts: all_songs, shuffle: lambda(&:reverse))
  end

  context "when started on the last song" do
    let(:queue) { tune(3) }

    it "plays it to the end" do
      jukebox.run
      expect([played, sink.played]).to eq([[3], 400])
    end

    it "reports how the song ended" do
      expect(jukebox.run).to eq(:finished)
    end

    it "shows the song, its number and its length" do
      jukebox.run
      expect(console.statuses.last).to include(song: 3, songs: 3, length: 30.0)
    end
  end

  it "plays just the tune's own song" do
    jukebox.run
    expect(played).to eq([1])
  end

  it "shows no modes" do
    jukebox.run
    expect(console.statuses.last[:notes]).to eq([])
  end

  context "with all songs on" do
    let(:queue) { tune(2, all_songs: true) }

    it "moves on to the next song when one ends" do
      jukebox.run
      expect(played).to eq([2, 3])
    end

    it "reports how the last song ended" do
      expect(jukebox.run).to eq(:finished)
    end

    it "shows it on the status line" do
      jukebox.run
      expect(console.statuses.last[:notes]).to eq(["all songs"])
    end
  end

  context "with → pressed" do
    let(:queue) { tune(2) }
    let(:script) { { 3 => [:next_song] } }

    it "moves on to the next song" do
      jukebox.run
      expect(played).to eq([2, 3])
    end
  end

  context "with → pressed on the last song" do
    let(:queue) { tune(3) }
    let(:script) { { 3 => [:next_song] } }

    it "stays on it" do
      jukebox.run
      expect(played).to eq([3])
    end
  end

  context "with ← pressed" do
    let(:queue) { tune(2) }
    let(:script) { { 3 => [:previous_song] } }

    it "goes back a song" do
      jukebox.run
      expect(played).to eq([2, 1])
    end
  end

  context "with ← pressed and all songs on" do
    let(:queue) { tune(2, all_songs: true) }
    let(:script) { { 3 => [:previous_song] } }

    it "goes back a song and plays on from there" do
      jukebox.run
      expect(played).to eq([2, 1, 2, 3])
    end
  end

  context "with ← pressed on the first song" do
    let(:script) { { 3 => [:previous_song] } }

    it "stays on it" do
      jukebox.run
      expect(played).to eq([1])
    end
  end

  context "with n pressed on the only tune" do
    let(:script) { { 3 => [:next] } }

    it "stays on it" do
      jukebox.run
      expect(played).to eq([1])
    end
  end

  context "with a pressed" do
    let(:queue) { tune(2) }
    let(:script) { { 3 => [:all_songs] } }

    it "plays on through the tune's songs" do
      jukebox.run
      expect(played).to eq([2, 3])
    end

    it "shows it on the status line" do
      jukebox.run
      expect(console.statuses.last[:notes]).to eq(["all songs"])
    end
  end

  context "with l pressed on the last song and all songs on" do
    let(:queue) { tune(3, all_songs: true) }
    let(:script) { { 3 => [:loop], 80 => [:quit] } }

    it "goes on to the first" do
      jukebox.run
      expect(played).to eq([3, 1, 2])
    end

    it "shows it on the status line" do
      jukebox.run
      expect(console.statuses.last[:notes]).to eq(["loop", "all songs"])
    end
  end

  context "with a queue of tunes" do
    let(:queue) { tunes(2, 1, 3) }

    it "plays each tune's own song in turn" do
      jukebox.run
      expect(console.statuses.map { |status| status[:songs] }.uniq).to eq([2, 1, 3])
    end

    context "with n pressed" do
      let(:script) { { 3 => [:next] } }

      it "cuts the first tune short and moves on to the next" do
        jukebox.run
        expect([console.statuses.map { |status| status[:songs] }.uniq, sink.played < 1200]).to eq([[2, 1, 3], true])
      end
    end

    context "with p pressed on the second tune" do
      let(:script) { { 40 => [:previous] } }

      it "goes back a tune and plays on from there" do
        jukebox.run
        expect(console.statuses.map { |status| status[:songs] }.chunk_while(&:==).map(&:first)).to eq([2, 1, 2, 1, 3])
      end
    end
  end

  context "with a queue of tunes and all songs on" do
    let(:queue) { tunes(2, 1, 3, all_songs: true) }

    it "plays each tune's songs in turn" do
      jukebox.run
      expect(played).to eq([1, 2, 1, 1, 2, 3])
    end

    context "with n pressed" do
      let(:script) { { 3 => [:next] } }

      it "leaves the rest of the tune's songs" do
        jukebox.run
        expect(played).to eq([1, 1, 1, 2, 3])
      end
    end

    context "with s pressed" do
      let(:script) { { 3 => [:shuffle] } }

      it "plays the rest of the queue in the shuffled order" do
        jukebox.run
        expect(played).to eq([1, 2, 1, 2, 3, 1])
      end

      it "shows it on the status line" do
        jukebox.run
        expect(console.statuses.last[:notes]).to eq(["shuffle", "all songs"])
      end
    end
  end

  context "with q pressed" do
    let(:queue) { tune(2, all_songs: true) }
    let(:script) { { 3 => [:quit] } }

    it "stops" do
      expect(jukebox.run).to eq(:stopped)
    end

    it "plays no further song" do
      jukebox.run
      expect(played).to eq([2])
    end
  end

  context "with Ctrl-C pressed" do
    let(:queue) { tune(2, all_songs: true) }
    let(:renderer) do
      lambda do |_entry, song, _rate|
        played << song
        InterruptingRenderer.new
      end
    end

    it "plays no further song" do
      jukebox.run
      expect(played).to eq([2])
    end
  end

  context "with space pressed twice" do
    let(:queue) { tune(3) }
    let(:script) { { 3 => [:pause], 8 => [:pause] } }

    it "shows the pause while it lasts" do
      jukebox.run
      paused = console.statuses.map { |status| status[:notes].include?("paused") }
      expect(paused.chunk_while(&:==).map(&:first)).to eq([false, true, false])
    end

    it "then plays the song out" do
      jukebox.run
      expect(sink.played).to eq(400)
    end
  end

  context "when the tune can't keep up" do
    let(:queue) { tune(3) }
    let(:renderer) { ->(_entry, _song, _rate) { FakeRenderer.new(sink, frames: 20, size: 20, cost: 0.04) } }

    it "says so on the status line" do
      jukebox.run
      expect(console.statuses.last[:notes]).to include("below real time")
    end
  end
end
