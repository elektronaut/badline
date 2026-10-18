# frozen_string_literal: true

require "spec_helper"
require "badline/cbm2"

describe Badline::CBM2::P500::IEEELayout do
  # The first bytes of each primitive in 901234-02, each seven bytes above
  # the B series': TALK's and LISTEN's ORA of the device in A, SECOND's and
  # TKSA's JSR to the byte sender, CIOUT's PHA, UNTALK's and UNLISTEN's
  # command and ACPTR's read of TPI1's port A.
  entries = {
    talk: [0x09, 0x40, 0xd0, 0x02], listen: [0x09, 0x20, 0x48], second: [0x20, 0xc0, 0xf2],
    tksa: [0x20, 0xc0, 0xf2, 0xa9, 0x3d], ciout: [0x48, 0xa5, 0xaa], untalk: [0xa9, 0x5f, 0xd0, 0x02],
    unlisten: [0xa9, 0x3f, 0x20, 0x3d, 0xf2], acptr: [0xad, 0x00, 0xde]
  }

  let(:layout) { described_class::LAYOUT }
  let(:kernal) { Badline::ROM.read(Badline::CBM2::P500::Model::KERNALS.fetch("02")) }

  entries.each do |entry, bytes|
    it "finds #{entry}" do
      expect(kernal[layout.public_send(entry) - 0xe000, bytes.length]).to eq(bytes)
    end
  end

  it "finds ST where the ROM ORs status bits into it" do
    expect(kernal[0xfb6e - 0xe000, 3]).to eq([0x05, layout.zero_page.status, 0x85])
  end

  it "takes the device from A" do
    expect(layout.device_in_a).to be(true)
  end

  # ACPTR's end: PA's bits in $3D kept, and PA0 set.
  it "leaves port A as ACPTR does" do
    expect(layout.byte_received(Badline::CBM2::P500.new.bus)).to eq(0x3d)
  end

  # UNLISTEN's end: PA $FD, then ATN let go.
  it "leaves port A as UNLISTEN does" do
    expect(layout.release_serial_lines(Badline::CBM2::P500.new.bus)).to eq(0xfd)
  end
end
