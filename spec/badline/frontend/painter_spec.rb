# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Painter do
  describe ".fit" do
    it "cuts a long name in its middle, keeping its start and end" do
      expect(described_class.fit("Last Ninja (Disk 1 of 2)(Side B).d64", 25)).to eq("Last Ninja ...Side B).d64")
    end

    it "leaves a name that fits alone" do
      expect(described_class.fit("game.d64", 25)).to eq("game.d64")
    end
  end
end
