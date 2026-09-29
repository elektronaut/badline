# frozen_string_literal: true

require "spec_helper"

describe Badline::Snapshot::MachineState do
  let(:state) { Badline::Snapshot::State.new([0, -1, 1, 2**40, -(2**33)], ["".b, "\x00\xffpath".b]) }

  it "reads back the State it encodes" do
    expect(described_class.decode(described_class.encode(state))).to eq(state)
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
