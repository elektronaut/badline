# frozen_string_literal: true

require "spec_helper"
require_relative "../support/pet_boot"

describe Badline::PET do
  include PETBoot

  it "is the 8032 by default" do
    expect(described_class.new.model.name).to eq("8032")
  end

  it "refuses a model it doesn't know" do
    expect { described_class.new(model: "9000") }.to raise_error(ArgumentError, /no PET model/)
  end

  it "refuses a RAM size no board has" do
    expect { described_class.new(model: "3032", ram_kb: 24) }.to raise_error(ArgumentError, /24K/)
  end

  it "runs a discrete board at 60 Hz whatever it's asked" do
    expect(described_class.new(model: "3032", refresh_hz: 50).refresh_hz).to eq(60)
  end

  describe "on a discrete board" do
    subject(:pet) { described_class.new(model: "3032") }

    it "holds the vertical drive line high for the first 200 lines" do
      pet.run_cycles((200 * 64) - 1)
      expect(pet.vertical_drive?).to be(true)
    end

    it "drops it for the last 60 of 260" do
      pet.run_cycles(200 * 64)
      lows = Array.new(60 * 64) { pet.vertical_drive?.tap { pet.cycle! } }
      expect([lows.uniq, pet.vertical_drive?]).to eq([[false], true])
    end

    it "reads it on the VIA's PB5" do
      pet.run_cycles(200 * 64)
      expect(pet.via.peek(0xe840) & 0x20).to eq(0)
    end

    it "flags its fall on PIA 1's CB1" do
      pet.run_cycles(200 * 64)
      expect(pet.pia1.crb & 0x80).to eq(0x80)
    end
  end

  describe "booted", :slow do
    {
      "2001" => ["*** COMMODORE BASIC ***", " 7167 BYTES FREE"],
      "3032" => ["### COMMODORE BASIC ###", " 31743 BYTES FREE"],
      "3032b" => ["### COMMODORE BASIC ###", " 31743 BYTES FREE"],
      "4032" => ["*** COMMODORE BASIC 4.0 ***", " 31743 BYTES FREE"],
      "8032" => ["*** COMMODORE BASIC 4.0 ***", " 31743 BYTES FREE"],
      "8096" => ["*** COMMODORE BASIC 4.0 ***", " 31743 BYTES FREE"]
    }.each do |model, (banner, bytes_free)|
      it "shows the #{model}'s banner and BYTES FREE, then READY, as xpet does" do
        expect(booted_once(model).last.first(5)).to eq([banner, "", bytes_free, "", "READY."])
      end
    end

    # Over the 300,000 cycles after the boot, which are 18 jiffies at 60 a
    # second. The 60 Hz editors' machines boot with 4K, which is quicker.
    [["2001", 50, nil, 60], ["4032", 50, nil, 50], ["8032", 50, nil, 50], ["4032", 60, 4, 60],
     ["8032", 60, 4, 60]].each do |model, refresh_hz, ram_kb, frames|
      context "with the #{model}'s #{refresh_hz} Hz editor" do
        let(:rates) { rates_once(model, 300_000, refresh_hz:, ram_kb:) }

        it "retraces #{frames} times a second" do
          expect(rates.retraces).to eq(frames * 3 / 10)
        end

        it "ticks the jiffy clock 60 times a second" do
          expect(rates.jiffies).to eq(18)
        end
      end
    end
  end
end
