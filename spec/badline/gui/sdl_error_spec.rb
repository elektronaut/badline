# frozen_string_literal: true

require "spec_helper"
require "badline/gui"

describe Badline::GUI::SDLError do
  describe ".check" do
    it "passes a non-negative result through" do
      expect(described_class.check(3)).to eq(3)
    end

    it "raises SDL's reason for a negative one" do
      allow(Badline::SDL).to receive(:SDL_GetError).and_return("No video")
      expect { described_class.check(-1) }.to raise_error(described_class, "No video")
    end
  end

  describe ".check_pointer" do
    it "passes a handle through" do
      expect(described_class.check_pointer(Fiddle::Pointer.new(0x1000))).to eq(Fiddle::Pointer.new(0x1000))
    end

    it "raises for a null handle" do
      expect { described_class.check_pointer(nil) }.to raise_error(described_class)
    end
  end
end
