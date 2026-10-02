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

  def place(tune, tunes) = @place = [tune, tunes]

  def seek_to = 0.2

  def status(**fields) = @statuses << fields.merge(place: @place)
end

# A renderer interrupted by Ctrl-C as it starts.
class InterruptingRenderer
  attr_accessor :from

  def stream = raise(Interrupt)
end

describe Badline::Audio::Jukebox do
  subject(:jukebox) do
    described_class.new(sink, console, queue:, renderer:, length: ->(_entry, subtune) { subtune * 10.0 })
  end

  let(:sink) { FakeSink.new(rate: 1000) }
  let(:console) { ScriptedConsole.new(sink, script) }
  let(:script) { {} }
  let(:queue) { tune(1) }
  let(:renderer) do
    lambda do |_entry, subtune, _rate|
      played << subtune
      FakeRenderer.new(sink, frames: 20, size: 20)
    end
  end

  def played = @played ||= []

  def tune(start, all_subtunes: false)
    Badline::Media::Queue.new([Badline::Media::Queue::Entry.new("tune.sid", part: start, parts: 3)],
                              all_parts: all_subtunes)
  end

  def tunes(*subtunes, all_subtunes: false)
    entries = subtunes.map { |parts| Badline::Media::Queue::Entry.new("#{parts}.sid", parts:) }
    Badline::Media::Queue.new(entries, all_parts: all_subtunes, shuffle: lambda(&:reverse))
  end

  context "when started on the last subtune" do
    let(:queue) { tune(3) }

    it "plays it to the end" do
      jukebox.run
      expect([played, sink.played]).to eq([[3], 400])
    end

    it "reports how the subtune ended" do
      expect(jukebox.run).to eq(:finished)
    end

    it "shows the subtune, its number and its length" do
      jukebox.run
      expect(console.statuses.last).to include(subtune: 3, subtunes: 3, length: 30.0)
    end
  end

  it "plays just the tune's own subtune" do
    jukebox.run
    expect(played).to eq([1])
  end

  it "shows no modes" do
    jukebox.run
    expect(console.statuses.last[:notes]).to eq([])
  end

  context "with all subtunes on" do
    let(:queue) { tune(2, all_subtunes: true) }

    it "moves on to the next subtune when one ends" do
      jukebox.run
      expect(played).to eq([2, 3])
    end

    it "reports how the last subtune ended" do
      expect(jukebox.run).to eq(:finished)
    end

    it "shows it on the status line" do
      jukebox.run
      expect(console.statuses.last[:notes]).to eq(["all subtunes"])
    end
  end

  context "with → pressed" do
    let(:queue) { tune(2) }
    let(:script) { { 3 => [:next_subtune] } }

    it "moves on to the next subtune" do
      jukebox.run
      expect(played).to eq([2, 3])
    end
  end

  context "with → pressed on the last subtune" do
    let(:queue) { tune(3) }
    let(:script) { { 3 => [:next_subtune] } }

    it "stays on it" do
      jukebox.run
      expect(played).to eq([3])
    end
  end

  context "with ← pressed" do
    let(:queue) { tune(2) }
    let(:script) { { 3 => [:previous_subtune] } }

    it "goes back a subtune" do
      jukebox.run
      expect(played).to eq([2, 1])
    end
  end

  context "with ← pressed and all subtunes on" do
    let(:queue) { tune(2, all_subtunes: true) }
    let(:script) { { 3 => [:previous_subtune] } }

    it "goes back a subtune and plays on from there" do
      jukebox.run
      expect(played).to eq([2, 1, 2, 3])
    end
  end

  context "with ← pressed on the first subtune" do
    let(:script) { { 3 => [:previous_subtune] } }

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
    let(:script) { { 3 => [:all_subtunes] } }

    it "plays on through the tune's subtunes" do
      jukebox.run
      expect(played).to eq([2, 3])
    end

    it "shows it on the status line" do
      jukebox.run
      expect(console.statuses.last[:notes]).to eq(["all subtunes"])
    end
  end

  context "with l pressed on the last subtune and all subtunes on" do
    let(:queue) { tune(3, all_subtunes: true) }
    let(:script) { { 3 => [:loop], 80 => [:quit] } }

    it "goes on to the first" do
      jukebox.run
      expect(played).to eq([3, 1, 2])
    end

    it "shows it on the status line" do
      jukebox.run
      expect(console.statuses.last[:notes]).to eq(["loop", "all subtunes"])
    end
  end

  context "with a queue of tunes" do
    let(:queue) { tunes(2, 1, 3) }

    it "plays each tune's own subtune in turn" do
      jukebox.run
      expect(console.statuses.map { |status| status[:subtunes] }.uniq).to eq([2, 1, 3])
    end

    it "shows each tune's place in the queue" do
      jukebox.run
      expect(console.statuses.map { |status| status[:place] }.uniq).to eq([[1, 3], [2, 3], [3, 3]])
    end

    context "with n pressed" do
      let(:script) { { 3 => [:next] } }

      it "cuts the first tune short and moves on to the next" do
        jukebox.run
        expect([console.statuses.map { |status| status[:subtunes] }.uniq, sink.played < 1200]).to eq([[2, 1, 3], true])
      end
    end

    context "with p pressed on the second tune" do
      let(:script) { { 40 => [:previous] } }

      it "goes back a tune and plays on from there" do
        jukebox.run
        counts = console.statuses.map { |status| status[:subtunes] }
        expect(counts.chunk_while(&:==).map(&:first)).to eq([2, 1, 2, 1, 3])
      end
    end
  end

  context "with a tune in the queue that can't play" do
    let(:queue) { tunes(2, 1, 3) }
    let(:renderer) do
      lambda do |entry, _subtune, _rate|
        next if entry.path == "1.sid"

        played << entry.path
        FakeRenderer.new(sink, frames: 20, size: 20)
      end
    end

    it "skips it" do
      jukebox.run
      expect(played).to eq(["2.sid", "3.sid"])
    end

    context "with p pressed on the tune after it" do
      let(:script) { { 40 => [:previous] } }

      it "skips it going back as well" do
        jukebox.run
        expect(played).to eq(["2.sid", "3.sid", "2.sid", "3.sid"])
      end
    end
  end

  context "with no tune in a looping queue that can play" do
    let(:queue) { tunes(2, 1).tap(&:toggle_loop) }
    let(:renderer) { ->(_entry, _subtune, _rate) {} }

    it "gives up once it has tried each" do
      expect(jukebox.run).to eq(:unplayable)
    end
  end

  context "with a queue of tunes and all subtunes on" do
    let(:queue) { tunes(2, 1, 3, all_subtunes: true) }

    it "plays each tune's subtunes in turn" do
      jukebox.run
      expect(played).to eq([1, 2, 1, 1, 2, 3])
    end

    context "with n pressed" do
      let(:script) { { 3 => [:next] } }

      it "leaves the rest of the tune's subtunes" do
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
        expect(console.statuses.last[:notes]).to eq(["shuffle", "all subtunes"])
      end
    end
  end

  context "with q pressed" do
    let(:queue) { tune(2, all_subtunes: true) }
    let(:script) { { 3 => [:quit] } }

    it "stops" do
      expect(jukebox.run).to eq(:stopped)
    end

    it "plays no further subtune" do
      jukebox.run
      expect(played).to eq([2])
    end
  end

  context "with Ctrl-C pressed" do
    let(:queue) { tune(2, all_subtunes: true) }
    let(:renderer) do
      lambda do |_entry, subtune, _rate|
        played << subtune
        InterruptingRenderer.new
      end
    end

    it "plays no further subtune" do
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

    it "then plays the subtune out" do
      jukebox.run
      expect(sink.played).to eq(400)
    end
  end

  context "when the tune can't keep up" do
    let(:queue) { tune(3) }
    let(:renderer) { ->(_entry, _subtune, _rate) { FakeRenderer.new(sink, frames: 20, size: 20, cost: 0.04) } }

    it "says so on the status line" do
      jukebox.run
      expect(console.statuses.last[:notes]).to include("below real time")
    end
  end

  context "when seeking" do
    let(:renderer) do
      ->(_entry, _subtune, _rate) { FakeRenderer.new(sink, frames: 20, size: 20).tap { |made| renderers << made } }
    end

    def renderers = @renderers ||= []

    {
      "a click on the time played" => [:seek, [0.0, 0.2]],
      "a step forward" => [:forward, [0.0, 9.0]],
      "a step back" => [:back, [0.0, 0.0]]
    }.each do |name, (action, froms)|
      context "with #{name}" do
        let(:script) { { 2 => [action] } }

        it "plays the subtune again from there" do
          jukebox.run
          expect(renderers.map(&:from)).to eq(froms)
        end
      end
    end
  end

  context "with an empty queue" do
    let(:queue) { Badline::Media::Queue.new([]) }
    let(:script) { { 3 => [:quit] } }

    it "waits on the console until asked to quit" do
      expect([jukebox.run, sink.played]).to eq([:stopped, 0])
    end
  end
end
