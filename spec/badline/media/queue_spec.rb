# frozen_string_literal: true

require "spec_helper"

describe Badline::Media::Queue do
  subject(:queue) { described_class.new(entries, all_parts:, shuffle: lambda(&:reverse)) }

  let(:entries) do
    [
      described_class::Entry.new("a.sid", part: 2, parts: 3),
      described_class::Entry.new("b.sid", part: 2, parts: 2),
      described_class::Entry.new("c.sid")
    ]
  end
  let(:all_parts) { false }

  def position = [queue.entry.path, queue.part]

  def walk(step, times) = Array.new(times) { [!queue.public_send(step).nil?, *position] }

  it "starts on the first entry's own part" do
    expect(position).to eq(["a.sid", 2])
  end

  it "plays one part of each entry unless told otherwise" do
    expect(described_class.new(entries).all_parts?).to be(false)
  end

  it "starts with shuffle and loop off" do
    expect([queue.shuffle?, queue.loop?]).to eq([false, false])
  end

  describe "#next_entry" do
    it "moves through the entries, each on its own part" do
      expect(walk(:next_entry, 2)).to eq([[true, "b.sid", 2], [true, "c.sid", 1]])
    end

    it "stays on the last entry" do
      2.times { queue.next_entry }
      expect(walk(:next_entry, 1)).to eq([[false, "c.sid", 1]])
    end

    context "with loop on" do
      before { queue.toggle_loop }

      it "goes on from the last entry to the first" do
        expect(walk(:next_entry, 3).last).to eq([true, "a.sid", 2])
      end
    end

    context "with all parts on" do
      let(:all_parts) { true }

      it "starts the next entry on its first part" do
        expect(walk(:next_entry, 1)).to eq([[true, "b.sid", 1]])
      end
    end
  end

  describe "#previous_entry" do
    it "stays on the first entry" do
      expect(walk(:previous_entry, 1)).to eq([[false, "a.sid", 2]])
    end

    it "moves back an entry, onto its own part" do
      2.times { queue.next_entry }
      expect(walk(:previous_entry, 2)).to eq([[true, "b.sid", 2], [true, "a.sid", 2]])
    end

    context "with loop on" do
      before { queue.toggle_loop }

      it "goes back from the first entry to the last" do
        expect(walk(:previous_entry, 1)).to eq([[true, "c.sid", 1]])
      end
    end

    context "with all parts on" do
      let(:all_parts) { true }

      it "starts the entry before on its first part" do
        queue.next_entry
        expect(walk(:previous_entry, 1)).to eq([[true, "a.sid", 1]])
      end
    end
  end

  describe "#next_part" do
    it "steps through the entry's parts and stops at its last" do
      expect(walk(:next_part, 2)).to eq([[true, "a.sid", 3], [false, "a.sid", 3]])
    end
  end

  describe "#previous_part" do
    it "steps back through the entry's parts and stops at its first" do
      expect(walk(:previous_part, 2)).to eq([[true, "a.sid", 1], [false, "a.sid", 1]])
    end
  end

  describe "#advance" do
    it "goes on to the next entry" do
      expect(walk(:advance, 2)).to eq([[true, "b.sid", 2], [true, "c.sid", 1]])
    end

    it "stops after the last entry" do
      2.times { queue.advance }
      expect(walk(:advance, 1)).to eq([[false, "c.sid", 1]])
    end

    context "with all parts on" do
      let(:all_parts) { true }

      it "plays out the entry's parts, then starts the next on its first" do
        expect(walk(:advance, 3)).to eq([[true, "a.sid", 3], [true, "b.sid", 1], [true, "b.sid", 2]])
      end
    end
  end

  describe "#toggle_all_parts" do
    it "keeps the part it's on" do
      queue.toggle_all_parts
      expect([queue.all_parts?, *position]).to eq([true, "a.sid", 2])
    end
  end

  describe "#toggle_shuffle" do
    it "turns shuffle on and off" do
      expect([queue.toggle_shuffle, queue.shuffle?, queue.toggle_shuffle]).to eq([true, true, false])
    end

    it "goes on from the current entry in the shuffled order" do
      queue.next_entry
      queue.toggle_shuffle
      expect(walk(:next_entry, 2)).to eq([[true, "c.sid", 1], [true, "a.sid", 2]])
    end

    it "goes back to the queue's own order when turned off" do
      queue.toggle_shuffle
      queue.next_entry
      queue.toggle_shuffle
      expect(walk(:previous_entry, 2)).to eq([[true, "b.sid", 2], [true, "a.sid", 2]])
    end
  end

  describe "#toggle_loop" do
    it "turns loop on and off" do
      expect([queue.toggle_loop, queue.loop?, queue.toggle_loop]).to eq([true, true, false])
    end
  end

  context "when empty" do
    let(:entries) { [] }

    it "has no entry" do
      expect([queue.entry, queue.size]).to eq([nil, 0])
    end

    it "doesn't move" do
      expect(%i[next_entry previous_entry next_part previous_part advance].map { |step| queue.public_send(step) })
        .to eq([nil] * 5)
    end

    it "turns shuffle on" do
      expect(queue.toggle_shuffle).to be(true)
    end
  end
end
