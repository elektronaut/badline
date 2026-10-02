# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::InfoView do
  def field(name, text) = Badline::Storage::STIL::Field.new(name, text)

  it "breaks text at spaces" do
    expect(described_class.wrap("one two three four", 9)).to eq(["one two", "three", "four"])
  end

  it "breaks a word longer than the line" do
    expect(described_class.wrap("abcdefghij", 4)).to eq(%w[abcd efgh ij])
  end

  it "runs a line of STIL's width on into the next, and ends a paragraph at a shorter one" do
    text = "#{'x' * 30} #{'y' * 40}\nruns on.\nA new paragraph."
    expect(described_class.paragraphs(text)).to eq(["#{'x' * 30} #{'y' * 40} runs on.", "A new paragraph."])
  end

  it "labels each field as STIL.txt does" do
    expect(described_class.layout([field("TITLE", "Base (0:53)"), field("ARTIST", "Tamayo Kawamoto")]))
      .to eq(["  TITLE: Base (0:53)", " ARTIST: Tamayo Kawamoto"])
  end

  context "with more lines than it shows" do
    subject(:view) { described_class.new(painter, buttons, 0) }

    let(:painter) { instance_double(Badline::Frontend::Painter, text: 0, box: nil) }
    let(:buttons) { instance_double(Badline::Frontend::Buttons, area: nil) }

    before { view.show(Array.new(40) { |index| field("COMMENT", "line #{index}") }, 1, []) }

    it "scrolls no further than its last line" do
      view.scroll(100)
      expect(view.offset).to eq(40 - described_class::ROWS)
    end

    it "scrolls to where the bar is clicked" do
      view.scroll_along(described_class::HEIGHT / 2)
      expect(view.offset).to eq(20)
    end
  end
end
