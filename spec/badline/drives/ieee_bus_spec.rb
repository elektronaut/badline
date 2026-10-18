# frozen_string_literal: true

require "spec_helper"

describe Badline::Drives::IEEEBus do
  subject(:bus) { described_class.new }

  # A drive that pulls NDAC, and NRFD too while ATN is low.
  let(:drive) do
    Class.new do
      attr_reader :written

      def host_written! = @written = true

      def ieee_low_lines(atn) = atn ? Badline::Drives::IEEEBus::NRFD | Badline::Drives::IEEEBus::NDAC : 0x0800
    end.new
  end

  it "carries the controller's lines alone with no drive on it" do
    expect(bus.low_lines(described_class::ATN | 0x12)).to eq(described_class::ATN | 0x12)
  end

  it "adds the lines each drive pulls" do
    bus.attach(drive)
    expect(bus.low_lines(0x12)).to eq(described_class::NDAC | 0x12)
  end

  it "tells each drive whether ATN is low" do
    bus.attach(drive)
    expect(bus.low_lines(described_class::ATN)).to eq(described_class::ATN | described_class::NRFD |
                                                      described_class::NDAC)
  end

  it "holds the lines the controller pushes, and tells the drives" do
    bus.attach(drive)
    bus.host_lines = described_class::DAV
    expect([bus.host_lines, drive.written]).to eq([described_class::DAV, true])
  end

  it "takes a drive off" do
    bus.attach(drive)
    bus.detach(drive)
    expect(bus.low_lines(0)).to eq(0)
  end

  it "keeps a drive attached twice once" do
    2.times { bus.attach(drive) }
    expect(bus.drives.length).to eq(1)
  end
end
