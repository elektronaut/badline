# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"

describe Badline::Chips::PIA::KeyedState do
  include KeyedOracle

  # Port A's DDR and output written, CA2 pulsing on each read of port A,
  # CB2 handshaking on each write to port B, and CA1 and CB1 flagged.
  def busy_pia
    Badline::Chips::PIA.new.tap do |pia|
      [[0, 0x0f], [1, 0x2d], [0, 0x05], [2, 0xff], [3, 0x24], [2, 0x81]].each { |reg, value| pia.poke(reg, value) }
      pia.peek(0)
      pia.ca1 = false
      pia.cb1 = false
    end
  end

  def restored(pia)
    Badline::Chips::PIA.new.tap { |fresh| keyed_round_trip(pia, fresh) }
  end

  def outputs(pia) = [pia.port_a_output, pia.port_b_output, pia.cra, pia.crb, pia.ca2_output, pia.cb2_output, pia.irq?]

  it "saves again the fields it loaded" do
    pia = busy_pia
    expect(saved_fields(restored(pia))).to eq(saved_fields(pia))
  end

  it "drives the control lines as the saved PIA does" do
    pia = busy_pia
    expect(outputs(restored(pia))).to eq(outputs(pia))
  end

  it "ends a pulse under way on the same cycle" do
    pia = busy_pia
    copy = restored(pia)
    [pia, copy].each(&:cycle!)
    expect(outputs(copy)).to eq(outputs(pia))
  end
end
