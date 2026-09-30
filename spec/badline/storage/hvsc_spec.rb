# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::HVSC do
  let(:dir) { Dir.mktmpdir }
  let(:root) { File.join(dir, "C64Music") }
  let(:document) { File.join(root, "DOCUMENTS", "STIL.txt") }
  let(:tune_path) { File.join(root, "MUSICIANS", "H", "tune.sid") }

  before do
    FileUtils.mkdir_p(File.dirname(document))
    FileUtils.mkdir_p(File.dirname(tune_path))
    File.write(document, "")
  end

  after { FileUtils.remove_entry(dir) }

  describe ".document" do
    it "finds the document above the tune" do
      expect(described_class.document(tune_path, "STIL.txt")).to eq(document)
    end

    it "falls back to $HVSC_BASE" do
      allow(ENV).to receive(:fetch).with("HVSC_BASE", nil).and_return(root)
      expect(described_class.document(File.join(dir, "tune.sid"), "STIL.txt")).to eq(document)
    end

    it "is nil when there is no document" do
      expect(described_class.document(tune_path, "BUGlist.txt")).to be_nil
    end
  end

  describe ".path" do
    it "is the tune's path from the collection's root" do
      expect(described_class.path(tune_path, document)).to eq("/MUSICIANS/H/tune.sid")
    end

    it "is nil for a tune outside the collection" do
      expect(described_class.path(File.join(dir, "tune.sid"), document)).to be_nil
    end
  end
end
