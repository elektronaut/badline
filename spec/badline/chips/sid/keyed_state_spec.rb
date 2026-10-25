# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"

# The SID's keyed fields, saved again the same: a SID caught up and saved,
# loaded into a fresh one, saves the same fields, with what the registers
# decode to worked out from them, and runs on as the saved one does.
module SIDKeyedSamples
  extend KeyedOracle

  # Three voices through pulse, noise, sawtooth+triangle and the test bit,
  # with ring modulation, hard sync, gates opening and closing, and the
  # filter swept.
  WRITES = {
    0 => [[0x18, 0x1f], [0x17, 0xf7], [0x16, 0x40], [0x05, 0x09], [0x06, 0xa0], [0x01, 0x11], [0x02, 0x00],
          [0x03, 0x08], [0x04, 0x41], [0x0c, 0x22], [0x0d, 0x84], [0x08, 0x2a], [0x0b, 0x81], [0x13, 0x00],
          [0x14, 0xf0], [0x0f, 0x07], [0x12, 0x15]],
    3_000 => [[0x04, 0x49], [0x16, 0x80]],
    3_200 => [[0x04, 0xc1], [0x12, 0x33]],
    6_000 => [[0x0b, 0x80], [0x15, 0x05], [0x18, 0x7f]],
    9_000 => [[0x04, 0x30], [0x12, 0x14], [0x17, 0x31]],
    12_000 => [[0x04, 0xf1], [0x0b, 0x89], [0x0b, 0x11]]
  }.freeze

  module_function

  def normalize(sid)
    sid.voices.each { |voice| voice.waveform.output }
    saved_fields(sid)
  end

  def fresh(model, synthesizing)
    Badline::Chips::SID.new(model:).tap { |sid| sid.synthesize! if synthesizing }
  end

  def write(sid, cycle)
    WRITES.fetch(cycle, []).each { |reg, value| sid.poke(0xd400 + reg, value) }
  end

  def check(sid, model, synthesizing, cycle)
    sid.catch_up!
    target = fresh(model, synthesizing)
    problems = keyed_round_trip(sid, target).report.lines(verbose: true)
    problems << "saves other fields" unless normalize(sid) == normalize(target)
    problems.map { |line| "cycle #{cycle}: #{line}" }
  end

  # Samples the SID every 7 cycles of the script.
  def scripted(model, synthesizing)
    @scripted ||= {}
    @scripted[[model, synthesizing]] ||= begin
      sid = fresh(model, synthesizing)
      problems = []
      15_000.times do |cycle|
        write(sid, cycle)
        sid.cycle!
        problems.concat(check(sid, model, synthesizing, cycle)) if (cycle % 7).zero?
      end
      problems
    end
  end

  # A SID loaded part way through the script runs on through the rest of
  # it as the saved one does, and records what it records when both are
  # recording.
  def runs_on?(model, recording: false)
    sid = fresh(model, true)
    sid.record(rate: 44_100) if recording
    3_100.times do |cycle|
      write(sid, cycle)
      sid.cycle!
    end
    sid.drain_samples
    target = fresh(model, true)
    keyed_round_trip(sid, target)
    target.record(rate: 44_100) if recording
    (3_100...10_000).each do |cycle|
      [sid, target].each do |each|
        write(each, cycle)
        each.cycle!
      end
    end
    [sid.drain_samples, sid.output, normalize(sid)] == [target.drain_samples, target.output, normalize(target)]
  end
end

describe Badline::Chips::SID::KeyedState do
  %i[mos6581 mos8580].each do |model|
    context "with the #{model}" do
      it "saves the same fields through the script, synthesizing" do
        expect(SIDKeyedSamples.scripted(model, true).first(5)).to be_empty
      end

      it "saves the same fields through the script, not synthesizing" do
        expect(SIDKeyedSamples.scripted(model, false).first(5)).to be_empty
      end

      it "runs on as the saved SID does" do
        expect(SIDKeyedSamples.runs_on?(model)).to be(true)
      end

      it "records on from the saved SID's window" do
        expect(SIDKeyedSamples.runs_on?(model, recording: true)).to be(true)
      end
    end
  end
end
