# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::MenuDialogs, "#ask_name" do
  subject(:dialogs) { described_class.new(painter, buttons, media, Badline::Options.parse([]), snapshots) }

  let(:painter) { instance_double(Badline::Frontend::Painter, text: 0, box: nil) }
  let(:buttons) { Badline::Frontend::Buttons.new(painter, [1, 2, 3, 4]) }
  let(:media) { Badline::Frontend::MenuMedia.new("", false) }
  let(:snapshots) { instance_double(Badline::Frontend::Snapshots, named?: taken, save_named: true) }
  let(:taken) { false }

  # Presses the keys, laying the dialog out before each, as the menu's
  # frames do.
  def press(*scancodes) = scancodes.map { |scancode| dialogs.draw(0, 0, 300).then { dialogs.key(scancode) } }.last

  before { dialogs.ask_name("Game 1") }

  it "saves under the name Return takes" do
    press(40)
    expect(snapshots).to have_received(:save_named).with("Game 1", replace: false)
  end

  it "closes once it has saved" do
    press(40)
    expect(dialogs.open?).to be(false)
  end

  context "with a save of that name" do
    let(:taken) { true }

    it "overwrites it once OVERWRITE is pressed" do
      press(40, 81, 40)
      expect(snapshots).to have_received(:save_named).with("Game 1", replace: true)
    end

    it "saves nothing when CANCEL is pressed" do
      press(40, 40)
      expect(snapshots).not_to have_received(:save_named)
    end

    it "goes back to the name with CANCEL" do
      press(40, 40)
      expect(dialogs.open?).to be(true)
    end
  end
end
