# frozen_string_literal: true

require "spec_helper"
require "badline/cbm2"

describe Badline::CBM2::IEEEPorts do
  subject(:machine) { Badline::CBM2.new }

  let(:ports) { machine.ieee }

  # A drive that pulls the lines it's given.
  def pull(lines)
    drive = Struct.new(:lines) do
      def host_written!; end
      def ieee_low_lines(_atn) = lines
    end.new(lines)
    ports.bus.attach(drive)
  end

  it "pulls the data lines the CIA's port A drives low" do
    { 0xdc02 => 0xff, 0xdc00 => 0xfe }.each { |addr, value| machine.poke(addr, value) }
    expect(ports.low_lines & Badline::Drives::IEEEBus::DIO).to eq(0x01)
  end

  it "pulls ATN, DAV, EOI, NDAC and NRFD from TPI1's PA3-PA7 driven low" do
    { 0xde03 => 0xf8, 0xde00 => 0x00 }.each { |addr, value| machine.poke(addr, value) }
    expect(ports.low_lines).to eq(0x1f00)
  end

  it "reads a line a drive pulls low on the port it comes in on" do
    pull(Badline::Drives::IEEEBus::NRFD | 0x80)
    expect([machine.peek(0xde00) & 0xf8, machine.peek(0xdc00)]).to eq([0x78, 0x7f])
  end
end
