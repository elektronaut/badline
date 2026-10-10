# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Buttons do
  context "with the SID player's buttons" do
    subject(:buttons) { described_class.new(painter, [theme::TEXT, theme::BRIGHT, theme::BACKGROUND]) }

    let(:theme) { Badline::Frontend::PlayerTheme }
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
      expect(painter).to have_received(:text).with(12, 22, "LOOP", theme::BRIGHT)
    end
  end

  context "with a menu's rows" do
    subject(:buttons) { described_class.new(painter, [1, 2, 3, 4]) }

    let(:painter) { instance_double(Badline::Frontend::Painter, text: 0, box: nil) }

    before do
      buttons.row([0, 0, 200], "INSERT", :insert)
      buttons.toggle([0, 14, 200], "WRITABLE", :writable, [%w[OFF ON], %i[protect unprotect], 0])
      buttons.row([0, 28, 200], "EJECT", :eject)
    end

    it "finds a toggle's choice before its row" do
      expect([buttons.action_at(5, 16), buttons.action_at(190, 16)]).to eq(%i[writable unprotect])
    end

    it "stands a toggle's row for its next choice" do
      expect([buttons.resolve(:writable), buttons.resolve(:insert)]).to eq(%i[unprotect insert])
    end

    it "moves the focus down the rows, past the choices" do
      buttons.focus = :insert
      expect(Array.new(3) { buttons.shift(1, 0).then { buttons.focus } }).to eq(%i[writable eject eject])
    end

    it "moves the focus from the first row when it has none" do
      buttons.shift(1, 0)
      expect(buttons.focus).to eq(:insert)
    end
  end
end
