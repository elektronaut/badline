# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../../support/blank_disk"

# The chains here are the ones a true 2031 and 8050 lay out in VICE for the
# same writes.
describe Badline::Storage::DiskImage::Bam do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def blocks(count) = Array.new(count * 254) { |i| i & 0xff }

  def chain(image, name)
    track, sector = image.first_block(name)
    links = []
    while track != 0
      links << [track, sector]
      track, sector = image.read_block(track, sector).first(2)
    end
    links
  end

  describe "a file that fills track 17 on a .d64" do
    subject(:image) { Badline::Storage::D64Image.new(blank_d64(File.join(dir, "a.d64"))) }

    before { image.write_file("ten", blocks(41)) }

    it "comes round each track one short of the interleave, and moves on to track 16 from the same sector" do
      expect(chain(image, "ten").first(23))
        .to eq([[17, 0], [17, 10], [17, 20], [17, 8], [17, 18], [17, 6], [17, 16], [17, 4], [17, 14], [17, 2],
                [17, 12], [17, 1], [17, 11], [17, 3], [17, 13], [17, 5], [17, 15], [17, 7], [17, 17], [17, 9],
                [17, 19], [16, 7], [16, 17]])
    end
  end

  describe "a file past a full track 38 on a .d80" do
    subject(:image) { Badline::Storage::D80Image.new(blank_d80(File.join(dir, "a.d80"))) }

    before do
      image.write_file("fill", blocks(27))
      image.write_file("big", blocks(41))
    end

    # Five apart round each track, one short past its last sector.
    let(:on_track40) do
      [[40, 0], [40, 5], [40, 10], [40, 15], [40, 20], [40, 25], [40, 2], [40, 7], [40, 12], [40, 17], [40, 22],
       [40, 1], [40, 6], [40, 11], [40, 16], [40, 21], [40, 26], [40, 3], [40, 8], [40, 13], [40, 18], [40, 23],
       [40, 4], [40, 9], [40, 14], [40, 19], [40, 24]]
    end

    it "lays its blocks five sectors apart on track 40, then 41 from the same sector" do
      expect(chain(image, "big").first(29)).to eq(on_track40 + [[41, 1], [41, 6]])
    end
  end
end
