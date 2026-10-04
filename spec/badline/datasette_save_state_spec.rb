# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

describe Badline::Datasette, "#save_state" do
  include SnapshotScenarios

  let(:dir) { Dir.mktmpdir }
  let(:path) do
    pulses = Array.new(400) { |i| i.even? ? 0x30 : 0x42 }
    File.join(dir, "noise.tap").tap do |file|
      File.binwrite(file, "C64-TAPE-RAW".b + [1, 0, 0, 0, pulses.length].pack("C4V") + pulses.pack("C*"))
    end
  end
  let(:saved) do
    described_class.new(Badline::Storage::TAP.new(path)).tap do |datasette|
      datasette.play!
      datasette.motor = true
      5001.times { datasette.cycle! }
    end
  end

  it "puts the tape back in where it had played to" do
    target = round_trip(saved, described_class.new)
    expect(state_differences(saved, target)).to be_empty
  end

  def edges(datasette, cycles)
    count = 0
    datasette.on_flag { count += 1 }
    cycles.times { datasette.cycle! }
    count
  end

  it "plays on as the saved one does" do
    target = round_trip(saved, described_class.new)
    expect(edges(target, 3000)).to eq(edges(saved, 3000))
  end

  it "keeps its tape when it's the same one" do
    target = described_class.new(Badline::Storage::TAP.new(path))
    tape = target.tape
    round_trip(saved, target)
    expect(target.tape).to equal(tape)
  end

  it "takes the tape out when the saved one had none" do
    target = described_class.new(Badline::Storage::TAP.new(path))
    expect(round_trip(described_class.new, target).tape).to be_nil
  end

  def saved_state
    out = Badline::Snapshot::StateWriter.new
    saved.save_state(out)
    out.state
  end

  it "plays on once the tape's file is gone" do
    state = saved_state
    File.delete(path)
    target = described_class.new
    target.load_state(Badline::Snapshot::StateReader.new(state))
    expect(edges(target, 3000)).to eq(edges(saved, 3000))
  end

  it "plays on for a detached reader" do
    target = described_class.new
    target.load_state(Badline::Snapshot::StateReader.new(saved_state, detached: true))
    expect(edges(target, 3000)).to eq(edges(saved, 3000))
  end

  it "puts in the saved tape when the file at its path has changed" do
    state = saved_state
    target = described_class.new(Badline::Storage::TAP.new(path))
    File.binwrite(path, "C64-TAPE-RAW".b + [1, 0, 0, 0, 2].pack("C4V") + "\x30\x30".b)
    target.load_state(Badline::Snapshot::StateReader.new(state))
    expect(edges(target, 3000)).to eq(edges(saved, 3000))
  end

  it "doesn't press the keys through the sense handler" do
    target = described_class.new
    senses = []
    target.on_sense_change { senses << :sensed }
    round_trip(saved, target)
    expect(senses).to be_empty
  end
end
