# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"

# The datasette's keyed fields against its positional save_state.
describe Badline::Drives::Datasette::KeyedState do
  include KeyedOracle

  let(:dir) { Dir.mktmpdir }
  let(:path) do
    pulses = Array.new(400) { |i| i.even? ? 0x30 : 0x42 }
    File.join(dir, "noise.tap").tap do |file|
      File.binwrite(file, "C64-TAPE-RAW".b + [1, 0, 0, 0, pulses.length].pack("C4V") + pulses.pack("C*"))
    end
  end
  let(:saved) do
    Badline::Drives::Datasette.new(Badline::Storage::TAP.new(path)).tap do |datasette|
      datasette.play!
      datasette.motor = true
      5001.times { datasette.cycle! }
    end
  end

  it "puts the tape back in where it had played to, from the bytes it holds" do
    target = Badline::Drives::Datasette.new
    keyed_round_trip(saved, target)
    File.delete(path)
    expect(positional(target)).to eq(positional(saved))
  end

  it "takes the tape out when the module holds none" do
    target = Badline::Drives::Datasette.new(Badline::Storage::TAP.new(path))
    keyed_round_trip(Badline::Drives::Datasette.new, target)
    expect(target.tape).to be_nil
  end
end
