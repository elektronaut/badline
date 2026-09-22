# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::SongLengths do
  subject(:database) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "Songlengths.md5") }
  let(:body) do
    <<~DATABASE
      [Database]
      ; /DEMOS/0-9/10_Orbyte.sid
      5f08a730b280e54fd1e75a7046b93fdc=1:17
      ; /DEMOS/0-9/12th_Sector_Music.sid
      c7c299ce06ec5ccffb2261fb11b42a73=4:33.108
      ; /GAMES/A-F/Comic_Bakery.sid
      4d566160c89bad11cea9b644108ee7ef=0:42 0:24 1:36
    DATABASE
  end

  before { File.write(path, body) }
  after { FileUtils.remove_entry(dir) }

  describe "#lengths" do
    it "reads a time in minutes and seconds" do
      expect(database.lengths("5f08a730b280e54fd1e75a7046b93fdc")).to eq([77.0])
    end

    it "keeps the milliseconds" do
      expect(database.lengths("c7c299ce06ec5ccffb2261fb11b42a73")).to eq([273.108])
    end

    it "reads one time per song" do
      expect(database.lengths("4d566160c89bad11cea9b644108ee7ef"))
        .to eq([42.0, 24.0, 96.0])
    end

    it "matches an upper-case digest" do
      expect(database.lengths("5F08A730B280E54FD1E75A7046B93FDC")).to eq([77.0])
    end

    it "is nil for a tune it doesn't list" do
      expect(database.lengths("0" * 32)).to be_nil
    end
  end

  describe ".locate" do
    let(:tune_path) { File.join(dir, "C64Music", "MUSICIANS", "tune.sid") }

    before do
      FileUtils.mkdir_p(File.join(dir, "C64Music", "DOCUMENTS"))
      FileUtils.mkdir_p(File.dirname(tune_path))
      FileUtils.mv(path, File.join(dir, "C64Music", "DOCUMENTS"))
    end

    it "finds the database above the tune" do
      expect(described_class.locate(tune_path))
        .to eq(File.join(dir, "C64Music", "DOCUMENTS", "Songlengths.md5"))
    end

    it "falls back to $HVSC_BASE" do
      loose = File.join(Dir.mktmpdir, "tune.sid")
      allow(ENV).to receive(:fetch).with("HVSC_BASE", nil)
                                   .and_return(File.join(dir, "C64Music"))
      expect(described_class.locate(loose))
        .to eq(File.join(dir, "C64Music", "DOCUMENTS", "Songlengths.md5"))
    end

    it "is nil when there is no database" do
      expect(described_class.locate(File.join(Dir.mktmpdir, "tune.sid"))).to be_nil
    end
  end
end
