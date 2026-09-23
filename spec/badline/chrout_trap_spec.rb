# frozen_string_literal: true

require "spec_helper"

describe Badline::ChroutTrap do
  let(:computer) { Badline::Computer.new }
  let(:capture) { computer.capture_output }

  before do
    capture
    # CHROUT is JMP ($0326); point the vector somewhere harmless
    computer.ram.write(0x0326, [0x00, 0x60])
  end

  def chrout(byte)
    computer.cpu.a = byte
    computer.cpu.program_counter = described_class::ADDRESS
    computer.cpu.step!
  end

  describe "printing characters" do
    before do
      [0x48, 0x49, 0x20, 0xd0, 0x31, 0x0d].each { |byte| chrout(byte) }
    end

    specify { expect(capture.output).to eq("hi P1\n") }
  end

  describe "control and graphics characters" do
    before do
      chrout(0x93)
      chrout(0x05)
    end

    specify { expect(capture.output).to eq("") }
  end

  describe "execution continuing into the ROM routine" do
    before { chrout(0x41) }

    specify { expect(computer.cpu.program_counter).to eq(0x6000) }
    specify { expect(computer.cpu.stack_pointer).to eq(0xff) }
  end

  describe "with the KERNAL ROM banked out" do
    before do
      computer.address_bus.poke(0x00, 0x2f)
      computer.address_bus.poke(0x01, 0x35)
      chrout(0x41)
    end

    specify { expect(capture.output).to eq("") }
  end

  describe "installing the trap" do
    specify { expect(computer.capture_output).to be(capture) }
  end
end
