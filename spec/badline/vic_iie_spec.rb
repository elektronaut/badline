# frozen_string_literal: true

require "spec_helper"

# What the C128 drives in the VIC-IIe for $D030's FAST and TEST bits.
RSpec.describe Badline::VIC do
  let(:vic) { described_class.new(model: :mos8566) }

  describe "#take_cpu_bus" do
    # Raster 51 is a bad line. Cell 10's c-access runs in column 23 and its
    # g-access in column 24.
    let(:col) { 10 }

    before do
      vic.poke(0xd011, 0x1b)
      vic.poke(0xd021, 6)
    end

    # Runs to the end of raster 51 with the CPU's bytes in every cycle.
    def run_fast(phi1, phi2, register_access: false)
      (52 * 63).times do
        vic.cycle!
        vic.take_cpu_bus(phi1, phi2, register_access) if vic.rasterline == 51
      end
    end

    it "draws the phi1 byte with the phi2 byte's low nibble as colour" do
      run_fast(0x81, 0x37)
      expect(vic.display[(51 * vic.width) + ((col + 16) * 8), 8]).to eq([7, 6, 6, 6, 6, 6, 6, 7])
    end

    it "reads $ff for the video matrix" do
      run_fast(0x81, 0x37)
      expect(vic.character_buffer[col]).to eq(0xff)
    end

    it "takes the byte of a VIC register access for the video matrix" do
      run_fast(0x81, 0x37, register_access: true)
      expect(vic.character_buffer[col]).to eq(0x37)
    end
  end

  describe "#test_step!" do
    def step_raster
      vic.test_step!
      vic.rasterline
    end

    it "moves the raster counter on a line" do
      vic.test_step!
      expect(vic.rasterline).to eq(1)
    end

    it "adds nothing in the line's last cycle, which steps it anyway" do
      62.times { vic.cycle! }
      vic.test_step!
      expect(vic.rasterline).to eq(0)
    end

    it "takes two steps from the frame's last line to line 0" do
      vic.restore_line(311)
      expect(Array.new(2) { step_raster }).to eq([311, 0])
    end

    it "leaves the line the beam draws behind the raster counter" do
      vic.test_step!
      63.times { vic.cycle! }
      expect([vic.rasterline, vic.output_line]).to eq([2, 1])
    end

    it "puts the beam back on the raster line in the vertical sync" do
      vic.restore_line(300)
      vic.test_step!
      (5 * 63).times { vic.cycle! }
      expect(vic.output_line).to eq(vic.rasterline)
    end
  end
end
