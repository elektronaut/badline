# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"
require_relative "../../../support/keyed_oracle"

describe Badline::Plus4::KeyboardPort::KeyedState do
  include KeyedOracle

  it "loads the 6529's latch" do
    saved, target = Array.new(2) { Badline::Plus4.new.keyboard_port }
    saved.poke(0xfd30, 0x7f)
    keyed_round_trip(saved, target)
    expect(target.output).to eq(0x7f)
  end
end
