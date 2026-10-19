# frozen_string_literal: true

require "spec_helper"

describe Badline::Drives::IEEEModels do
  it "keeps an image in the drive there when it reads it" do
    expect(described_class.taking("disk.d82", "8250", "2031")).to eq("8250")
  end

  it "picks the machine's own model next" do
    expect(described_class.taking("disk.D82", "2031", "8250")).to eq("8250")
  end

  it "picks the image's own model last" do
    expect(described_class.taking("disk.d80", "2031", "8250")).to eq("8050")
  end

  it "has no model for an image none reads" do
    expect(described_class.taking("disk.d81", nil, "2031")).to be_nil
  end
end
