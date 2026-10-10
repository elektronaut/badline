# frozen_string_literal: true

require "spec_helper"

describe Badline::Snapshot::MachineState do
  let(:state) { Badline::Snapshot::State.new([0, -1, 1, 2**40, -(2**33)], ["".b, "\x00\xffpath".b]) }

  it "reads back the State it encodes" do
    expect(described_class.decode(described_class.encode(state))).to eq(state)
  end

  it "reads back the largest values a native build can hold" do
    edges = Badline::Snapshot::State.new([(2**62) - 1, -(2**62)], [])
    expect(described_class.decode(described_class.encode(edges))).to eq(edges)
  end

  it "refuses a value a native build can't hold, as the native build does" do
    too_large = Badline::Snapshot::State.new([2**62], [])
    expect { described_class.encode(too_large) }.to raise_error(RangeError, /too large/)
  end

  it "reads back the State a BADLINE module holds" do
    expect(described_class.state(described_class.section(state))).to eq(state)
  end

  it "refuses a module another badline version wrote" do
    section = described_class.section(state).with(major: 1)
    expect { described_class.state(section) }.to raise_error(Badline::Snapshot::FormatError, /another badline/)
  end

  it "fails on a damaged module" do
    section = described_class.section(state).with(data: "damaged".b)
    expect { described_class.state(section) }.to raise_error(Badline::Snapshot::FormatError, /damaged/)
  end

  it "fails on a payload cut short" do
    bytes = described_class.encode(state)
    expect { described_class.decode(bytes.byteslice(0, bytes.bytesize - 2)) }
      .to raise_error(Badline::Snapshot::FormatError, /ends early/)
  end
end
