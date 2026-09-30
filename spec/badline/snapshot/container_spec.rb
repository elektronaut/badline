# frozen_string_literal: true

require "spec_helper"
require "zlib"

describe Badline::Snapshot::Container do
  let(:sections) do
    [Badline::Snapshot::Section.new(name: "MAINCPU", major: 1, minor: 2, data: "\x01\x02".b),
     Badline::Snapshot::Section.new(name: "SID", major: 1, minor: 5, data: "".b)]
  end
  let(:bytes) { described_class.new(sections).to_s }

  it "starts with the magic, the format version and the machine" do
    expect(bytes.byteslice(0, 37)).to eq("VICE Snapshot File\x1a\x02\x00C64SC#{"\0" * 11}".b)
  end

  it "heads each module with its name, version and length" do
    expect(bytes.byteslice(37, 22)).to eq("MAINCPU#{"\0" * 9}\x01\x02\x18\x00\x00\x00".b)
  end

  it "reads back what it writes" do
    expect(described_class.parse(bytes).sections).to eq(sections)
  end

  it "reads a gzipped snapshot" do
    expect(described_class.parse(Zlib.gzip(bytes)).sections).to eq(sections)
  end

  it "finds a module by name" do
    expect(described_class.parse(bytes)["SID"].version).to eq("1.5")
  end

  it "keeps the VICE version block of a snapshot VICE wrote" do
    version = "#{"VICE Version\x1a".b}\x03\x07\x01\x00\x10\x00\x00\x00".b
    vice = bytes.byteslice(0, 37) + version + bytes.byteslice(37..)
    expect(described_class.parse(vice).to_s).to eq(vice)
  end

  it "refuses a file that isn't a snapshot" do
    expect { described_class.parse("C64-TAPE-RAW") }
      .to raise_error(Badline::Snapshot::FormatError, /not a VICE snapshot/)
  end

  it "refuses a module that runs past the end" do
    expect { described_class.parse(bytes.byteslice(0, bytes.bytesize - 1)) }
      .to raise_error(Badline::Snapshot::FormatError, /ends early/)
  end

  it "refuses a module shorter than its header" do
    broken = bytes.dup
    broken.setbyte(37 + 18, 3)
    expect { described_class.parse(broken) }.to raise_error(Badline::Snapshot::FormatError, /bad length/)
  end

  it "refuses a module name longer than 16 bytes" do
    long = Badline::Snapshot::Section.new(name: "A" * 17, major: 0, minor: 0, data: "")
    expect { described_class.new([long]).to_s }.to raise_error(ArgumentError)
  end
end
