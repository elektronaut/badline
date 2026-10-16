# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Storage::D82Image do
  include BlankDisk

  subject(:image) { described_class.new(blank_d82(path, name: "BLANK82", id: "CD")) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "blank.d82") }

  after { FileUtils.remove_entry(dir) }

  it "puts the second side's zones on tracks 78 to 154" do
    expect([78, 116, 117, 154].map { |track| image.sectors_in(track) }).to eq([29, 29, 27, 23])
  end

  it "counts the free blocks of both sides from the four BAM blocks" do
    expect(image.directory.blocks_free).to eq(4133)
  end

  it "finds the second side's last block" do
    expect(image.read_block(154, 22)).to eq(Array.new(256, 0))
  end
end
