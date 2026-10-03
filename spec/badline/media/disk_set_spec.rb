# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Media::DiskSet do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def files(*names) = names.each { |name| FileUtils.touch(File.join(dir, name)) }

  def disks_with(name) = described_class.around(File.join(dir, name)).map { |path| File.basename(path) }

  it "orders TOSEC's disks and sides" do
    files("Ninja (Disk 2 of 2)(Side A).d64", "Ninja (Disk 1 of 2)(Side B).d64", "Ninja (Disk 1 of 2)(Side A).d64")
    expect(disks_with("Ninja (Disk 1 of 2)(Side B).d64"))
      .to eq(["Ninja (Disk 1 of 2)(Side A).d64", "Ninja (Disk 1 of 2)(Side B).d64", "Ninja (Disk 2 of 2)(Side A).d64"])
  end

  it "reads short markers such as disk1 and s2" do
    files("Pirates disk1.d64", "Pirates disk2.d64", "Ultima s1.d64", "Ultima s2.d64")
    expect([disks_with("Pirates disk2.d64"), disks_with("Ultima s1.d64")])
      .to eq([["Pirates disk1.d64", "Pirates disk2.d64"], ["Ultima s1.d64", "Ultima s2.d64"]])
  end

  it "counts sides by letter" do
    files("Bard Side B.d64", "Bard Side A.d64")
    expect(disks_with("Bard Side B.d64")).to eq(["Bard Side A.d64", "Bard Side B.d64"])
  end

  it "orders a trailing number as a number" do
    files("HVSC_1.d64", "HVSC_2.d64", "HVSC_10.d64")
    expect(disks_with("HVSC_2.d64")).to eq(%w[HVSC_1.d64 HVSC_2.d64 HVSC_10.d64])
  end

  it "takes a trailing letter" do
    files("Game-a.d64", "Game-b.d64")
    expect(disks_with("Game-b.d64")).to eq(%w[Game-a.d64 Game-b.d64])
  end

  it "leaves a sequel out of a set without its first disk" do
    files("Summer Games.d64", "Summer Games 2.d64")
    expect(disks_with("Summer Games 2.d64")).to eq(["Summer Games 2.d64"])
  end

  it "keeps to the disk's own name" do
    files("Pirates disk1.d64", "Pirates disk2.d64", "Elite disk1.d64")
    expect(disks_with("Elite disk1.d64")).to eq(["Elite disk1.d64"])
  end

  it "keeps to the disk's own format" do
    files("Pirates disk1.d64", "Pirates disk2.g64")
    expect(disks_with("Pirates disk1.d64")).to eq(["Pirates disk1.d64"])
  end

  it "has a tape on its own" do
    files("Game 1.tap", "Game 2.tap")
    expect(disks_with("Game 1.tap")).to eq(["Game 1.tap"])
  end
end
