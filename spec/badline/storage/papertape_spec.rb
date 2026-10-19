# frozen_string_literal: true

require "spec_helper"

# The format is the KIM-1 User Manual's appendix F.
describe Badline::Storage::Papertape do
  # A record of `bytes` at `address`, with its checksum.
  def record(address, bytes)
    fields = [bytes.size, address >> 8, address & 0xff] + bytes
    sum = fields.sum
    ";#{(fields + [sum >> 8, sum & 0xff]).map { |byte| format('%02X', byte) }.join}"
  end

  def tape(*records) = "#{records.join("\r\n")}\r\n#{record(records.size, [])}\r\n\u0000\u0000\u0013"

  let(:text) { tape(record(0x0200, [0xa9, 0x01]), record(0x17f0, [0xea])) }

  it "reads each record's address and bytes" do
    records = described_class.new(text).records
    expect(records.map { |entry| [entry.address, entry.bytes] }).to eq([[0x0200, [0xa9, 0x01]], [0x17f0, [0xea]]])
  end

  it "starts where the first record goes" do
    expect(described_class.new(text).start_address).to eq(0x0200)
  end

  it "keeps the text up to the last record's end" do
    expect(described_class.new(text).text).to end_with(";0000020002")
  end

  it "takes lowercase hex and lines ending in LF" do
    expect(described_class.new(tape(record(0x0300, [0xff])).downcase.delete("\r")).records.size).to eq(1)
  end

  it "refuses a bad checksum" do
    expect { described_class.new(text.sub("A901", "A902")) }.to raise_error(described_class::FormatError, /\$0200/)
  end

  it "refuses a tape without its last record" do
    expect { described_class.new(record(0x0200, [0xea])) }.to raise_error(described_class::FormatError)
  end

  it "refuses a tape cut off in a record" do
    expect { described_class.new(";1802") }.to raise_error(described_class::FormatError)
  end
end
