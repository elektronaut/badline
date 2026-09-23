# frozen_string_literal: true

require "spec_helper"

describe Badline::KernalTrap::Drive::Parameters do
  it "reads parameters separated by spaces, commas and cursor-rights" do
    expect(described_class.parse("2 0,18\x1d1")).to eq([2, 0, 18, 1])
  end

  it "reads a character outside $30 to $3F as a parameter of 0" do
    expect(described_class.parse("18,\x02")).to eq([18, 0])
  end

  it "skips the character that ends a parameter" do
    expect(described_class.parse("18x5")).to eq([18, 5])
  end

  it "keeps the last three digits of a long parameter" do
    expect(described_class.parse("1234")).to eq([234])
  end

  it "reads nothing from an empty string" do
    expect(described_class.parse("")).to eq([])
  end
end
