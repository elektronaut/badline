# frozen_string_literal: true

require "spec_helper"

describe Badline::Datasette do
  subject(:datasette) { described_class.new }

  let(:tape) { instance_double(Badline::Storage::TAP, rewind: nil, end?: false) }
  let(:edges) { [] }

  before do
    allow(tape).to receive(:next_pulse).and_return(4, 6, nil)
    datasette.on_flag { edges << datasette }
    datasette.insert(tape)
  end

  def run(cycles)
    cycles.times { datasette.cycle! }
  end

  def stall(cycles)
    datasette.motor = false
    run(cycles)
    datasette.motor = true
  end

  describe "#cycle!" do
    before do
      datasette.play!
      datasette.motor = true
    end

    it "holds the flag line until the pulse has played out" do
      run(3)
      expect(edges.length).to eq(0)
    end

    it "pulses the flag line after the first pulse length" do
      run(4)
      expect(edges.length).to eq(1)
    end

    it "spaces the next edge by the next pulse length" do
      run(9)
      expect(edges.length).to eq(1)
    end

    it "pulses again once the second pulse has played out" do
      run(10)
      expect(edges.length).to eq(2)
    end

    it "stops pulsing at the end of the tape" do
      run(100)
      expect(edges.length).to eq(2)
    end

    it "does not run with the motor stopped" do
      datasette.motor = false
      run(100)
      expect(edges).to be_empty
    end

    it "does not run with no key pressed" do
      datasette.stop!
      run(100)
      expect(edges).to be_empty
    end

    it "resumes where the motor stopped" do
      run(2)
      stall(100)
      run(2)
      expect(edges.length).to eq(1)
    end
  end

  describe "#running?" do
    it "needs a key, the motor and a tape" do
      datasette.play!
      datasette.motor = true
      expect(datasette).to be_running
    end

    it "is false with an empty deck" do
      datasette.eject
      datasette.play!
      datasette.motor = true
      expect(datasette).not_to be_running
    end
  end

  describe "the cassette sense line" do
    it "reads high with no key pressed" do
      expect(datasette).not_to be_sense_low
    end

    it "reads low while a key is pressed" do
      datasette.play!
      expect(datasette).to be_sense_low
    end

    it "reports the key going down" do
      changes = 0
      datasette.on_sense_change { changes += 1 }
      datasette.play!
      expect(changes).to eq(1)
    end

    it "does not report a key that was already down" do
      datasette.play!
      changes = 0
      datasette.on_sense_change { changes += 1 }
      datasette.play!
      expect(changes).to eq(0)
    end
  end

  describe "#insert" do
    before do
      datasette.play!
      datasette.motor = true
    end

    it "rewinds the tape" do
      datasette.insert(tape)
      expect(tape).to have_received(:rewind).twice
    end

    it "drops the pulse in flight" do
      allow(tape).to receive(:next_pulse).and_return(4)
      run(2)
      datasette.insert(tape)
      run(3)
      expect(edges).to be_empty
    end
  end

  describe "#eject" do
    before { datasette.play! }

    it "releases the keys" do
      datasette.eject
      expect(datasette).not_to be_playing
    end

    it "empties the deck" do
      datasette.eject
      expect(datasette.tape).to be_nil
    end
  end
end
