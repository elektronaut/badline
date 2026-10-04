# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::NameField do
  subject(:field) { described_class.new(nil).tap { |name_field| name_field.open("SAVE AS", "Game 1") } }

  def type(*scancodes, shift: false) = scancodes.map { |scancode| field.key(scancode, shift) }.last

  it "types letters, digits and the full stop" do
    type(44, 7, 30, 55)
    expect(field.text).to eq("Game 1 d1.")
  end

  it "types capitals with Shift" do
    type(7, shift: true)
    expect(field.text).to eq("Game 1D")
  end

  it "deletes with Backspace" do
    type(42, 42)
    expect(field.text).to eq("Game")
  end

  it "takes the name with Return and leaves it with Esc" do
    expect([type(40), type(41)]).to eq(%i[done cancel])
  end

  it "stops at its length" do
    type(*[4] * 40)
    expect(field.text.length).to eq(described_class::COLUMNS)
  end
end
