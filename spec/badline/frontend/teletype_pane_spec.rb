# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::TeletypePane do
  subject(:pane) { described_class.new }

  let(:teletype) { Struct.new(:baud, :output).new(9600, +"") }
  let(:computer) { Struct.new(:teletype).new(teletype) }

  def print_text(text)
    teletype.output << text
    pane.follow(computer)
    pane.lines
  end

  it "prints a line, RETURN and LINE FEED starting the next" do
    expect(print_text("\x7f\r\n\x00KIM\r\n0000 00 ").first(3)).to eq(["", "KIM", "0000 00"])
  end

  it "goes on to the next line past the last column" do
    expect(print_text("A" * 73)[1]).to eq("A")
  end

  it "scrolls the page up from the last line" do
    expect(print_text("FIRST\r\n#{"\n" * 24}LAST").values_at(0, 23)).to eq(["", "LAST"])
  end

  it "draws the characters in ink on paper" do
    print_text("K")
    expect(pane.display[(described_class::TOP * described_class::WIDTH) + 8, 8]).to include(described_class::INK)
  end
end
