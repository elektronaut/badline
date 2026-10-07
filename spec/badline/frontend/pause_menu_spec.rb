# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::PauseMenu do
  subject(:menu) do
    options = Badline::Options.parse([])
    described_class.new(painter, options, Badline::Frontend::Snapshots.new(computer, options))
  end

  let(:painter) { instance_double(Badline::Frontend::Painter, text: 0, box: nil) }
  let(:computer) { Badline::Computer.new }
  let(:controls) { Badline::Frontend::Controls.new(computer) }

  before { menu.show(computer, controls, instance_double(Badline::Frontend::Sound, on?: false, muted?: false)) }

  # Presses the keys, drawing the menu before each, as its frames do, and
  # returns what the last asked the app for.
  def press(*scancodes) = scancodes.map { |scancode| menu.draw.then { menu.key(scancode) } }.last

  def focused = menu.instance_variable_get(:@buttons).focus

  it "opens on the snapshots section" do
    expect(focused).to eq(:snapshots)
  end

  it "opens each section the arrows reach" do
    press(81, 81, 81, 81)
    expect(focused).to eq(:ports)
  end

  it "opens on the section it's given" do
    menu.section = 2
    menu.show(computer, controls, instance_double(Badline::Frontend::Sound, on?: false, muted?: false))
    expect(focused).to eq(:datasette)
  end

  it "reaches Quick open past the last section" do
    press(*[81] * 7)
    expect(focused).to eq(:quick_open)
  end

  it "goes into the page with Right, down its rows, and back with Left" do
    expect([press(81, 79, 81).then { focused }, press(80).then { focused }]).to eq(%i[eject_disk drive])
  end

  it "presses the row with Return" do
    press(81, 81, 81, 81, 79, 40)
    expect(controls.pot).to eq(:mouse1)
  end

  it "asks the app to resume with Esc or F9" do
    expect([press(41), press(Badline::Frontend::Keys::F9)]).to eq(%i[resume resume])
  end

  it "asks the app to quit from the power section" do
    expect(press(*[81] * 6, 79, 81, 81, 40)).to eq(:quit)
  end
end
