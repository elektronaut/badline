# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Media::DiskList do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def files(*names) = names.each { |name| FileUtils.touch(File.join(dir, name)) }

  def list(name, *lines) = File.join(dir, name).tap { |path| File.write(path, lines.map { |line| "#{line}\n" }.join) }

  def names(paths) = paths.map { |path| File.basename(path) }

  it "takes an .m3u's disks in its order, skipping blank lines and comments" do
    files("b.d64", "a.d64")
    expect(names(described_class.disks(list("game.m3u", "#EXTM3U", "b.d64", "", "a.d64")))).to eq(%w[b.d64 a.d64])
  end

  it "takes paths relative to the list" do
    FileUtils.mkdir(File.join(dir, "disks"))
    files("disks/one.d64")
    expect(described_class.disks(list("game.m3u", "disks/one.d64"))).to eq([File.join(dir, "disks/one.d64")])
  end

  it "takes absolute paths" do
    files("one.d64")
    expect(described_class.disks(list("game.m3u", File.join(dir, "one.d64")))).to eq([File.join(dir, "one.d64")])
  end

  it "leaves out an entry that isn't there" do
    files("one.d64")
    expect(names(described_class.disks(list("game.m3u", "one.d64", "missing.d64")))).to eq(%w[one.d64])
  end

  it "leaves out files that aren't disk images" do
    files("one.d64", "tune.sid")
    expect(names(described_class.disks(list("game.m3u", "tune.sid", "one.d64")))).to eq(%w[one.d64])
  end

  it "takes only unit 8's entries from a .vfl" do
    files("a.d64", "b.d64", "c.d64")
    vfl = list("game.vfl", "# Vice fliplist file", "", "UNIT 8", "a.d64", "c.d64", "UNIT 9", "b.d64")
    expect(names(described_class.disks(vfl))).to eq(%w[a.d64 c.d64])
  end

  it "has no disks for a list that isn't there" do
    expect(described_class.disks(File.join(dir, "missing.m3u"))).to eq([])
  end

  it "puts a list's first disk that's there in" do
    files("a.d64")
    expect(described_class.disk(list("game.m3u", "missing.d64", "a.d64"))).to eq(File.join(dir, "a.d64"))
  end

  it "puts any other path in as it is" do
    expect(described_class.disk("game.d64")).to eq("game.d64")
  end

  it "refuses a list with no disk that's there" do
    expect { described_class.disk(list("game.m3u", "missing.d64")) }.to raise_error(described_class::Error)
  end
end
