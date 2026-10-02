# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::STIL do
  subject(:stil) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "STIL.txt") }
  let(:body) do
    <<~STIL
      ##########################################################
      #  STIL - a sample
      ##########################################################

      ### /MUSICIANS/X/ #########################################

      /MUSICIANS/X/Example_Ed/
      COMMENT: A composer's directory.

      /MUSICIANS/X/Example_Ed/Covers.sid
      COMMENT: Covers from a demo,
               two lines long.
      (#1)
         NAME: Tune One
      (#3)
       AUTHOR: Someone Else
        TITLE: A Subtune [from An Album] (0:18)
       ARTIST: A Band
      COMMENT: Only the chorus.
        TITLE: Another Subtune (0:40)
       ARTIST: Another Band

      /MUSICIANS/X/Example_Ed/Café.sid
        TITLE: Für Elise
       ARTIST: Ludwig van Beethoven
    STIL
  end

  before { File.binwrite(path, body.encode(Encoding::ISO_8859_1).gsub("\n", "\r\n")) }
  after { FileUtils.remove_entry(dir) }

  def entry = stil.entry("/MUSICIANS/X/Example_Ed/Covers.sid")
  def names(fields) = fields.map(&:name)

  describe "#entry" do
    it "reads the fields for the whole tune" do
      expect(names(entry.fields)).to eq(%w[COMMENT])
    end

    it "joins a field's lines" do
      expect(entry.fields.first.text).to eq("Covers from a demo,\ntwo lines long.")
    end

    it "reads each subtune's fields" do
      expect(names(entry.subtune(3))).to eq(%w[AUTHOR TITLE ARTIST COMMENT TITLE ARTIST])
    end

    it "reads a field's text" do
      expect(entry.subtune(1).first.text).to eq("Tune One")
    end

    it "has no fields for a subtune it doesn't list" do
      expect(entry.subtune(2)).to eq([])
    end

    it "reads the list as ISO-8859-1" do
      expect(stil.entry("/MUSICIANS/X/Example_Ed/Café.sid").fields.first.text).to eq("Für Elise")
    end

    it "reads a directory's entry" do
      expect(stil.entry("/MUSICIANS/X/Example_Ed/").fields.first.text).to eq("A composer's directory.")
    end

    it "is nil for a tune it doesn't list" do
      expect(stil.entry("/MUSICIANS/X/Example_Ed/Missing.sid")).to be_nil
    end
  end

  describe "#entries" do
    it "lists every tune and directory" do
      expect(stil.entries.size).to eq(3)
    end
  end

  describe "Field#lines" do
    it "lays a field out as the list does" do
      expect(entry.fields.first.lines).to eq(["COMMENT: Covers from a demo,", "         two lines long."])
    end

    it "right-aligns a shorter name" do
      expect(entry.subtune(1).first.lines).to eq(["   NAME: Tune One"])
    end
  end

  describe ".locate" do
    let(:tune_path) { File.join(dir, "C64Music", "MUSICIANS", "tune.sid") }

    before do
      FileUtils.mkdir_p(File.join(dir, "C64Music", "DOCUMENTS"))
      FileUtils.mkdir_p(File.dirname(tune_path))
      FileUtils.mv(path, File.join(dir, "C64Music", "DOCUMENTS"))
    end

    it "finds the list above the tune" do
      expect(described_class.locate(tune_path)).to eq(File.join(dir, "C64Music", "DOCUMENTS", "STIL.txt"))
    end
  end
end
