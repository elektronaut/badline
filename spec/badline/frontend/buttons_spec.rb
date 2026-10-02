# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Buttons do
  subject(:buttons) { described_class.new(painter) }

  let(:painter) { instance_double(Badline::Frontend::Painter, text: 0, icon: nil, box: nil) }

  before do
    buttons.text(10, 20, "LOOP", :loop)
    buttons.icon(100, 20, :next, :next, scale: 2)
  end

  it "finds the action under a click" do
    expect([buttons.action_at(12, 25), buttons.action_at(110, 35)]).to eq(%i[loop next])
  end

  it "finds nothing between buttons" do
    expect(buttons.action_at(60, 25)).to be_nil
  end

  it "forgets the buttons when cleared" do
    buttons.forget
    expect(buttons.action_at(12, 25)).to be_nil
  end

  it "lights the button under the pointer" do
    buttons.point(12, 25)
    buttons.text(10, 20, "LOOP", :loop)
    expect(painter).to have_received(:text).with(12, 22, "LOOP", Badline::Frontend::SIDView::BRIGHT)
  end
end
