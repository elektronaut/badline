# frozen_string_literal: true

require "spec_helper"
require "badline/cbm2"

describe Badline::CBM2::IEEELayout do
  # The first bytes of each primitive: TALK's and LISTEN's ORA of the
  # device in A, SECOND's and TKSA's JSR to the byte sender, CIOUT's PHA,
  # UNTALK's and UNLISTEN's command and ACPTR's read of TPI1's port A.
  entries = {
    talk: [0x09, 0x40, 0xd0, 0x02], listen: [0x09, 0x20, 0x48], second: [0x20, 0xb9, 0xf2],
    tksa: [0x20, 0xb9, 0xf2, 0xa9, 0x39], ciout: [0x48, 0xa5, 0xaa], untalk: [0xa9, 0x5f, 0xd0, 0x02],
    unlisten: [0xa9, 0x3f, 0x20, 0x36, 0xf2], acptr: [0xad, 0x00, 0xde]
  }

  %w[04a 03b].each do |name|
    context "with KERNAL 901244-#{name}" do
      let(:layout) { described_class::LAYOUTS.fetch(name) }
      let(:kernal) { Badline::ROM.read(Badline::CBM2::Model::KERNALS.fetch(name)) }

      entries.each do |entry, bytes|
        it "finds #{entry}" do
          expect(kernal[layout.public_send(entry) - 0xe000, bytes.length]).to eq(bytes)
        end
      end

      it "finds ST where the ROM ORs status bits into it" do
        expect(kernal[0xfb5f - 0xe000, 3]).to eq([0x05, layout.zero_page.status, 0x85])
      end

      it "takes the device from A" do
        expect(layout.device_in_a).to be(true)
      end
    end
  end

  # UNLISTEN's end: PA $F8, or $F9 on 03b, then ATN let go.
  def released(name)
    machine = Badline::CBM2.new(kernal: name)
    described_class::LAYOUTS.fetch(name).release_serial_lines(machine.bus)
  end

  it "leaves port A as each KERNAL's UNLISTEN does" do
    expect([released("04a"), released("03b")]).to eq([0xf8, 0xf9])
  end

  # ACPTR's end: PA ANDed with $39, ORed with $01 on 03b.
  def received(name)
    machine = Badline::CBM2.new(kernal: name)
    machine.poke(0xde03, 0xff)
    machine.poke(0xde00, 0xfe)
    described_class::LAYOUTS.fetch(name).byte_received(machine.bus)
  end

  it "leaves PA0 as each KERNAL's ACPTR does" do
    expect([received("04a"), received("03b")]).to eq([0x38, 0x39])
  end
end
