# frozen_string_literal: true

require "spec_helper"

describe Badline::Storage::STIL::Credit do
  def field(name, text) = Badline::Storage::STIL::Field.new(name, text)

  let(:credits) do
    described_class.list([field("TITLE", "BGM1 [from the arcade game Commando] (0:00)"),
                          field("ARTIST", "Tamayo Kawamoto"),
                          field("COMMENT", "Played from the start."),
                          field("TITLE", "Base (0:53)"), field("ARTIST", "Tamayo Kawamoto"),
                          field("TITLE", "Level Complete (1:16-1:32)")])
  end

  it "reads each title's stretch of the subtune" do
    expect(credits.map { |credit| [credit.start, credit.finish] }).to eq([[0, -1], [53, -1], [76, 92]])
  end

  it "pairs each title with the artist after it" do
    expect(credits.map(&:text)).to eq(["BGM1 [from the arcade game Commando] - Tamayo Kawamoto",
                                       "Base - Tamayo Kawamoto", "Level Complete"])
  end

  it "follows the subtune as it plays" do
    expect([10, 60, 80, 100].map { |seconds| described_class.at(credits, seconds) })
      .to eq(["BGM1 [from the arcade game Commando] - Tamayo Kawamoto", "Base - Tamayo Kawamoto",
              "Level Complete", "Base - Tamayo Kawamoto"])
  end

  it "covers the whole subtune with a title that has no time" do
    untimed = described_class.list([field("TITLE", "Ghostbusters [from the movie]"),
                                    field("ARTIST", "Ray Parker, Jr.")])
    expect(described_class.at(untimed, 200)).to eq("Ghostbusters [from the movie] - Ray Parker, Jr.")
  end

  it "has nothing to say without titles" do
    expect(described_class.at(described_class.list([field("COMMENT", "Just a comment.")]), 0)).to eq("")
  end
end
