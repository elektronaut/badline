# frozen_string_literal: true

require "spec_helper"

describe Badline::Drive1581::Track do
  subject(:track) { described_class.standard(3, 1) { |sector| Array.new(512, sector) } }

  # A write track's bytes for one sector, as the DOS's format sends them,
  # with the sync marks they leave.
  def formatted(id, data, gap: 32)
    bytes = Array.new(gap, 0x4e) + Array.new(12, 0)
    syncs = Array.new(bytes.length, false)
    lay = lambda do |mark, field|
      bytes.push(0xa1, 0xa1, 0xa1, mark, *field, *described_class.field_crc(mark, field))
      syncs.push(true, true, true, *Array.new(field.length + 3, false))
    end
    lay.call(0xfe, id)
    bytes.concat(Array.new(22, 0x4e) + Array.new(12, 0))
    syncs.concat(Array.new(34, false))
    lay.call(0xfb, data)
    [bytes, syncs]
  end

  it "computes the CRC-CCITT the WD1772 writes, from $FFFF" do
    expect(described_class.crc("123456789".bytes)).to eq(0x29b1)
  end

  it "numbers a standard track's sectors from 1 to 10" do
    expect(track.sectors.map { |sector| sector.id.bytes[2] }).to eq((1..10).to_a)
  end

  it "carries the cylinder, side and size code in each ID" do
    expect(track.sectors.first.id.bytes).to eq([3, 1, 1, 2])
  end

  it "lays the first ID mark after 32 bytes of gap, 12 zeros and three syncs" do
    expect(track.sectors.first.id.mark).to eq(47)
  end

  it "spaces the sectors as the DOS's format does, 609 bytes apart" do
    expect(track.sectors[1].id.mark - track.sectors[0].id.mark).to eq(609)
  end

  it "puts each data mark 44 bytes after its ID mark" do
    expect(track.sectors[4].data.mark - track.sectors[4].id.mark).to eq(44)
  end

  it "finds the next ID at or after a place round the track" do
    expect(track.next_id(48).id.bytes[2]).to eq(2)
  end

  it "comes round to the first ID past the last" do
    expect(track.next_id(6000).id.bytes[2]).to eq(1)
  end

  it "lays the raw bytes out a turn long" do
    expect(track.raw.length).to eq(6250)
  end

  it "lays an ID field behind its sync marks in the raw bytes" do
    expect(track.raw[44, 5]).to eq([0xa1, 0xa1, 0xa1, 0xfe, 3])
  end

  it "spoils the CRC of a field that doesn't read back" do
    track.sectors.first.data.good = false
    raw = track.raw
    data = track.sectors.first.data
    expect(raw[data.mark + 513, 2]).not_to eq(described_class.field_crc(0xfb, data.bytes))
  end

  describe ".parse" do
    let(:parsed) { described_class.parse(*formatted([7, 0, 5, 2], Array.new(512, 0xe5))) }

    it "finds the ID a write track laid down" do
      expect(parsed.sectors.first.id.bytes).to eq([7, 0, 5, 2])
    end

    it "finds its data field, its length from the size code" do
      expect(parsed.sectors.first.data.bytes.length).to eq(512)
    end

    it "keeps where the ID mark lay" do
      expect(parsed.sectors.first.id.mark).to eq(47)
    end

    it "checks the fields' CRCs" do
      expect(parsed.sectors.first.data.good).to be(true)
    end

    it "takes an $A1 that wasn't a sync mark for data" do
      bytes, syncs = formatted([7, 0, 5, 2], Array.new(512, 0))
      expect(described_class.parse(bytes, syncs.map { false }).sectors).to be_empty
    end

    it "leaves an ID without a data field after it alone" do
      bytes, syncs = formatted([7, 0, 5, 2], [])
      expect(described_class.parse(bytes.first(60), syncs.first(60)).sectors.first.data).to be_nil
    end
  end
end
