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

  it "plays the VIA's CB2 once recorded" do
    pet = described_class.new
    pet.sound_source.record(rate: 44_100)
    pet.via.poke(0xe84c, 0xc0)
    pet.run_cycles(1_000)
    expect(pet.sound_source.drain_samples.min).to be < -10_000
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

    it "shows its 384 by 217 dot canvas whole, a dot to a pixel" do
      expect(pet.timing.to_h.slice(:crop, :pixel_width, :dots)).to eq(crop: [0, 0, 384, 217], pixel_width: 1, dots: 1)
    end

    it "runs 260 lines of 64 cycles a frame" do
      expect([pet.timing.cycles_per_line, pet.timing.lines_per_frame]).to eq([64, 260])
    end
  end

  describe "on an 80-column board" do
    subject(:pet) { described_class.new(model: "8032") }

    it "shows its 704 dots wide canvas two dots to a pixel" do
      expect(pet.timing.to_h.slice(:crop, :dots)).to eq(crop: [0, 0, 704, 273], dots: 2)
    end

    it "times its 50 Hz editor's frames" do
      expect(pet.timing.cycles_per_line * pet.timing.lines_per_frame).to eq(20_000)
    end

    it "times its 60 Hz editor's frames" do
      timing = described_class.new(model: "8032", refresh_hz: 60).timing
      expect(timing.cycles_per_line * timing.lines_per_frame).to eq(16_650)
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

    %w[2001 3032 4032 8032 8096].each do |model|
      it "prints 42 for PRINT 6*7 on the #{model}" do
        expect(typed_once(model, "print 6*7\r", 300_000)[5, 4]).to eq(["PRINT 6*7", " 42", "", "READY."])
      end
    end

    # The 4032 has the graphics keyboard and the 8032 the business one.
    # Each key held goes on the line after READY, after the keys held
    # before it.
    [["4032", :a, "A"], ["8032", :a, "A"], ["4032", :*, "*"], ["8032", :kp1, "1"]].each do |model, key, typed|
      it "types #{key} held down on the #{model}'s key matrix" do
        expect(pressed_once(model, key, 50_000, refresh_hz: 60, ram_kb: 4)[5]).to include(typed)
      end
    end

    # The top row of the first character on the screen.
    def first_row(pet)
      set = pet.via.ca2_output ? Badline::PET::Characters::TEXT : 0
      Badline::PET::Characters.new(pet.model.characters).rows[set | (pet.bus.screen.cells[0] << 3)]
    end

    # Where the first character's top row sits, as in xpet's screenshots.
    { "2001" => 8, "3032" => 8, "4032" => 36, "8032" => 11 }.each do |model, top|
      it "paints the #{model}'s first character on its canvas" do
        pet, = booted_once(model)
        canvas = pet.video
        dots = canvas.display[(top * canvas.width) + 32, 8].reduce(0) { |bits, dot| (bits << 1) | dot }
        expect(dots).to eq(first_row(pet))
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
