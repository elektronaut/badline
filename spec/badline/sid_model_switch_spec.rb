# frozen_string_literal: true

require "spec_helper"
require_relative "../support/snapshot_scenarios"

describe Badline::SID, "#model=" do
  include SnapshotScenarios

  # Each scenario reaches one per-model value: writes as [cycle, reg,
  # value], the cycle the chip switches on, the cycles it runs in all, how
  # often the probe reads it, and whether it reads the audio output.
  scenarios = {
    "the data bus fade" => { writes: [[0x2000, 0x00, 0xaa]], switch_at: 0x1000, cycles: 0xa5000, every: 0x800 },
    "the filter cutoff" => { writes: [[0, 0x01, 0x20], [0, 0x06, 0xf0], [0, 0x04, 0x21], [0, 0x16, 0x40],
                                      [0, 0x17, 0x01], [0, 0x18, 0x1f]],
                             switch_at: 3000, cycles: 6000, every: 7, audio: true },
    "the mixer DC offset" => { writes: [[0, 0x18, 0x0f], [3000, 0x18, 0x08]],
                               switch_at: 1000, cycles: 4000, every: 7, audio: true },
    "the waveform DAC midpoint and DC offset" => { writes: [[0, 0x01, 0x10], [0, 0x06, 0xf0], [0, 0x04, 0x21],
                                                            [0, 0x18, 0x0f]],
                                                   switch_at: 2000, cycles: 5000, every: 7, audio: true },
    "the combined waveforms" => { writes: [[0, 0x0f, 0x31], [0, 0x11, 0x08], [0, 0x12, 0x51], [3000, 0x12, 0x31]],
                                  switch_at: 1000, cycles: 6000, every: 3 },
    "the pulse and noise masks" => { writes: [[0, 0x0f, 0x21], [0, 0x11, 0x00], [0, 0x12, 0xc1]],
                                     switch_at: 10, cycles: 5000, every: 3 },
    "the top bit feedback" => { writes: [[0, 0x0f, 0x12], [0, 0x11, 0x08], [0, 0x12, 0x61]],
                                switch_at: 1000, cycles: 5000, every: 3 },
    "the triangle and sawtooth delay" => { writes: [[0, 0x0e, 0xff], [0, 0x0f, 0xff], [0, 0x12, 0x21]],
                                           switch_at: 100, cycles: 1100, every: 1 },
    "the shift register reset delay" => { writes: [[0, 0x0f, 0x80], [0, 0x12, 0x81], [0x2000, 0x12, 0x88],
                                                   [0x92000, 0x12, 0x80]],
                                          switch_at: 0x1000, cycles: 0x93000, every: 0x100 }
  }

  def probe(sid, audio) = [sid.osc3, sid.env3, sid[0xd41d], audio ? sid.output : 0]

  def play(sid, scenario, from, to)
    trace = []
    (from...to).each do |cycle|
      scenario[:writes].each { |at, reg, value| sid[0xd400 + reg] = value if at == cycle }
      sid.cycle!
      trace << probe(sid, scenario[:audio]) if (cycle % scenario[:every]).zero?
    end
    trace
  end

  def chip(model, audio: false)
    sid = described_class.new(model:, filter_chunk: 1)
    sid.synthesize! if audio
    sid
  end

  # The switch runs the cycles already passed on the old model, which a save
  # state would leave for the new one. It also carries the filter's cutoff
  # as the saving chip mapped it, so the one built as `model` maps it again
  # through its own curve.
  def built_from(sid, model)
    sid.catch_up!
    built = round_trip(sid, chip(model, audio: sid.synthesizing?))
    built.filter.write(0x16, built.register(0x16))
    built
  end

  # The traces after the switch of a SID switched to `to`, of one built as
  # `to` from its state before the switch, and of one left on `from`.
  def traces(scenario, from, to)
    switched = chip(from, audio: scenario[:audio])
    play(switched, scenario, 0, scenario[:switch_at])
    built = built_from(switched, to)
    stayed = round_trip(switched, chip(from, audio: scenario[:audio]))
    switched.model = to
    [switched, built, stayed].map { |sid| play(sid, scenario, scenario[:switch_at], scenario[:cycles]) }
  end

  # A SID switched part way through a scenario, and one built as `to` from
  # its state then.
  def switched_and_built(scenario, from, to)
    sid = chip(from)
    play(sid, scenario, 0, scenario[:switch_at])
    built = built_from(sid, to)
    sid.model = to
    [sid, built]
  end

  [%i[mos6581 mos8580], %i[mos8580 mos6581]].each do |from, to|
    context "when switched from the #{from} to the #{to}" do
      scenarios.each do |name, scenario|
        describe name do
          let(:played) { traces(scenario, from, to) }
          let(:at_switch) { switched_and_built(scenario, from, to) }

          it "plays as a SID built as the #{to}" do
            switched, built, = played
            expect(switched).to eq(built)
          end

          it "plays unlike the #{from}" do
            switched, _, stayed = played
            expect(switched).not_to eq(stayed)
          end

          # Only the 8580 keeps the delayed shapers.
          it "keeps the running state" do
            delayed = { "Badline::SID::Waveform" => %i[@delayed_sawtooth @delayed_triangle] }
            expect(state_differences(*at_switch, host: delayed)).to be_empty
          end
        end
      end

      it "reports the new model" do
        sid = chip(from)
        sid.model = to
        expect([sid.model, sid.filter.model]).to eq([to, to])
      end
    end
  end
end
