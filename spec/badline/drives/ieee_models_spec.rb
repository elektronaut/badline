# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

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

  describe "a .d90" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def image(size) = File.join(dir, "disk.d90").tap { |path| File.binwrite(path, "\0" * size) }

    it "goes in a D9090 when it is a D9090's size" do
      expect(described_class.taking(image(7_520_256), "9060", "2031")).to eq("9090")
    end

    it "goes in a D9060 when it is any other size" do
      expect(described_class.taking(image(1_000), "9090", "2031")).to eq("9060")
    end

    it "goes in the hard disk --drive-type names, whatever its size" do
      expect(described_class.taking(image(7_520_256), nil, "9060")).to eq("9060")
    end
  end
end
