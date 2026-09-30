# frozen_string_literal: true

require "spec_helper"

describe Badline::REU do
  let(:size_kb) { 512 }
  let(:bus) { Badline::Computer.new(reu: size_kb).address_bus }
  let(:reu) { bus.reu }

  before { bus.poke(0x01, 0x37) }

  # Sets up a transfer and writes the command that starts it.
  def transfer(command, c64: 0x1000, reu_address: 0x020000, length: 4, control: 0x00)
    bus.poke(0xdf02, c64 & 0xff)
    bus.poke(0xdf03, c64 >> 8)
    bus.poke(0xdf04, reu_address & 0xff)
    bus.poke(0xdf05, (reu_address >> 8) & 0xff)
    bus.poke(0xdf06, reu_address >> 16)
    bus.poke(0xdf07, length & 0xff)
    bus.poke(0xdf08, length >> 8)
    bus.poke(0xdf0a, control)
    bus.poke(0xdf01, command)
  end

  # Sets up a transfer and runs it to the end.
  def transfer!(...)
    transfer(...)
    run_dma
  end

  # Clocks the transfer with the given BA line per cycle until it hands
  # the bus back, returning the cycles it held it for.
  def run_dma(ba_line: [])
    held = 0
    loop do
      reu.dma_cycle!(ba_line.fetch(held, false))
      return held unless reu.holds_bus?

      held += 1
    end
  end

  describe "the registers" do
    it "reads the status with the 256K-chip bit on a 1750" do
      expect(bus.peek(0xdf00)).to eq(0x10)
    end

    context "with a 1700" do
      let(:size_kb) { 128 }

      it "reads the status without the 256K-chip bit" do
        expect(bus.peek(0xdf00)).to eq(0x00)
      end
    end

    it "powers on with the $FF00 trigger off" do
      expect(bus.peek(0xdf01)).to eq(0x10)
    end

    it "powers on with the whole length set" do
      expect([bus.peek(0xdf07), bus.peek(0xdf08)]).to eq([0xff, 0xff])
    end

    it "reads the unused bits of the interrupt and address control registers as 1" do
      bus.poke(0xdf09, 0x00)
      bus.poke(0xdf0a, 0x00)
      expect([bus.peek(0xdf09), bus.peek(0xdf0a)]).to eq([0x1f, 0x3f])
    end

    it "reads the bank register's top bits as 1" do
      bus.poke(0xdf06, 0x05)
      expect(bus.peek(0xdf06)).to eq(0xfd)
    end

    it "reads $FF past the registers" do
      expect([bus.peek(0xdf0b), bus.peek(0xdf1f)]).to eq([0xff, 0xff])
    end

    it "mirrors the registers every 32 bytes" do
      bus.poke(0xdf22, 0x42)
      expect(bus.peek(0xdfe2)).to eq(0x42)
    end

    it "reads back the C64 address it was given" do
      bus.poke(0xdf02, 0x42)
      expect(bus.peek(0xdf02)).to eq(0x42)
    end
  end

  describe "a transfer to the REU" do
    before do
      bus.ram.write(0x1000, [1, 2, 3, 4])
      transfer(0x90)
    end

    it "copies C64 memory into the REU" do
      run_dma
      expect(Array.new(4) { |i| reu.ram_peek(0x020000 + i) }).to eq([1, 2, 3, 4])
    end

    it "takes a cycle a byte" do
      expect(run_dma).to eq(4)
    end

    it "leaves the addresses past the block and the length at 1" do
      run_dma
      expect((2..8).map { |r| bus.peek(0xdf00 + r) }).to eq([0x04, 0x10, 0x04, 0x00, 0xfa, 0x01, 0x00])
    end

    it "flags the end of the block, and a read clears it" do
      run_dma
      expect([bus.peek(0xdf00), bus.peek(0xdf00)]).to eq([0x50, 0x10])
    end

    it "clears the execute bit and turns the $FF00 trigger off" do
      run_dma
      expect(bus.peek(0xdf01)).to eq(0x10)
    end

    it "waits for BA to go high before it starts" do
      reu.dma_cycle!(true)
      expect(reu.holds_bus?).to be(false)
    end

    it "waits out BA after each read" do
      expect(run_dma(ba_line: [false, true, true, false])).to eq(6)
    end

    it "reads the open bus at its registers while it runs" do
      reu.dma_cycle!(false)
      expect(bus.peek(0xdf00)).to eq(bus.vic.phi1_data)
    end

    it "ignores register writes while it runs" do
      reu.dma_cycle!(false)
      bus.poke(0xdf02, 0x99)
      run_dma
      expect(bus.peek(0xdf02)).to eq(0x04)
    end
  end

  describe "a transfer to the C64" do
    before do
      4.times { |i| reu.ram_poke(0x020000 + i, 0xa0 + i) }
      transfer(0x91)
    end

    it "copies REU memory into the C64" do
      run_dma
      expect(bus.ram.read(0x1000, 4)).to eq([0xa0, 0xa1, 0xa2, 0xa3])
    end

    it "writes through the first BA-low cycle and waits out the rest" do
      expect(run_dma(ba_line: [false, true, true, true, false])).to eq(6)
    end

    it "takes a cycle more when the VIC holds it off after the last write" do
      expect(run_dma(ba_line: [false, false, false, true, true, false])).to eq(6)
    end

    it "writes to the RAM under the CPU port at $00 and $01" do
      transfer(0x91, c64: 0x0000, length: 2)
      run_dma
      expect([bus.ram.peek(0x00), bus.ram.peek(0x01), bus.peek(0x01) & 0x07]).to eq([0xa0, 0xa1, 0x07])
    end
  end

  describe "a swap" do
    before do
      bus.ram.write(0x1000, [1, 2])
      reu.ram_poke(0x020000, 0xa0)
      reu.ram_poke(0x020001, 0xa1)
      transfer(0x92, length: 2)
    end

    it "exchanges C64 and REU memory" do
      run_dma
      expect([bus.ram.read(0x1000, 2), reu.ram_peek(0x020000), reu.ram_peek(0x020001)])
        .to eq([[0xa0, 0xa1], 1, 2])
    end

    it "takes two cycles a byte" do
      expect(run_dma).to eq(4)
    end
  end

  describe "a verify" do
    before do
      bus.ram.write(0x1000, [1, 2, 3, 4])
      4.times { |i| reu.ram_poke(0x020000 + i, i + 1) }
    end

    it "ends the block when every byte matches" do
      transfer(0x93)
      run_dma
      expect(bus.peek(0xdf00)).to eq(0x50)
    end

    it "stops at the first byte that differs" do
      reu.ram_poke(0x020000, 0x99)
      transfer(0x93)
      run_dma
      expect([bus.peek(0xdf00), bus.peek(0xdf02), bus.peek(0xdf07)]).to eq([0x30, 0x01, 0x03])
    end

    it "takes a cycle more when bytes are left" do
      reu.ram_poke(0x020000, 0x99)
      transfer(0x93)
      expect(run_dma).to eq(2)
    end

    it "ends the block after all when the last byte matches past a miss on the one before" do
      reu.ram_poke(0x020002, 0x99)
      transfer(0x93)
      run_dma
      expect(bus.peek(0xdf00)).to eq(0x70)
    end
  end

  describe "address control" do
    it "keeps the C64 address fixed" do
      bus.poke(0x1000, 0x42)
      transfer(0x90, control: 0x80)
      run_dma
      expect([reu.ram_peek(0x020003), bus.peek(0xdf02), bus.peek(0xdf03)]).to eq([0x42, 0x00, 0x10])
    end

    it "keeps the REU address fixed" do
      bus.ram.write(0x1000, [1, 2, 3, 4])
      transfer(0x90, control: 0x40)
      run_dma
      expect([reu.ram_peek(0x020000), bus.peek(0xdf04), bus.peek(0xdf06)]).to eq([4, 0x00, 0xfa])
    end
  end

  it "loads the registers back after an autoload transfer" do
    transfer(0xb0)
    run_dma
    expect((2..8).map { |r| bus.peek(0xdf00 + r) }).to eq([0x00, 0x10, 0x00, 0x00, 0xfa, 0x04, 0x00])
  end

  it "counts a length of 0 as 64K" do
    transfer(0x90, length: 0)
    expect(run_dma).to eq(0x10000)
  end

  it "wraps the REU address at 512K" do
    bus.ram.write(0x1000, [1, 2])
    transfer(0x90, reu_address: 0x07ffff, length: 2)
    run_dma
    expect([reu.ram_peek(0x07ffff), reu.ram_peek(0x000000), bus.peek(0xdf06)]).to eq([1, 2, 0xf8])
  end

  context "with a 1700" do
    let(:size_kb) { 128 }

    it "wraps the REU address at 128K" do
      bus.ram.write(0x1000, [1, 2])
      transfer(0x90, reu_address: 0x01ffff, length: 2)
      run_dma
      expect([reu.ram_peek(0x01ffff), reu.ram_peek(0x000000)]).to eq([1, 2])
    end
  end

  context "with a 1764" do
    let(:size_kb) { 256 }

    it "reads the latch above its 256K of DRAM" do
      bus.poke(0x1000, 0x5a)
      transfer!(0x90, length: 1)
      transfer!(0x91, c64: 0x2000, reu_address: 0x040000, length: 1)
      expect(bus.peek(0x2000)).to eq(0x5a)
    end
  end

  context "with 16M" do
    let(:size_kb) { 16_384 }

    it "keeps every bit of the bank register" do
      bus.ram.write(0x1000, [7])
      transfer(0x90, reu_address: 0xfe0000, length: 1)
      run_dma
      expect([reu.ram_peek(0xfe0000), bus.peek(0xdf06)]).to eq([7, 0xfe])
    end
  end

  describe "the $FF00 trigger" do
    before do
      bus.ram.write(0x1000, [1])
      transfer(0x80, length: 1)
    end

    it "arms a transfer without starting it" do
      expect(reu.dma?).to be(false)
    end

    it "starts the armed transfer on a write to $FF00" do
      bus.poke(0xff00, 0x00)
      run_dma
      expect(reu.ram_peek(0x020000)).to eq(1)
    end

    it "still writes $FF00" do
      bus.poke(0xff00, 0x42)
      expect(bus.ram.peek(0xff00)).to eq(0x42)
    end

    it "fires once" do
      bus.poke(0xff00, 0x00)
      run_dma
      bus.poke(0xff00, 0x00)
      expect(reu.dma?).to be(false)
    end
  end

  describe "the interrupt" do
    it "fires at the end of the block when enabled" do
      bus.poke(0xdf09, 0xc0)
      transfer(0x90)
      run_dma
      expect([reu.irq?, bus.peek(0xdf00)]).to eq([true, 0xd0])
    end

    it "is cleared by reading the status" do
      bus.poke(0xdf09, 0xc0)
      transfer(0x90)
      run_dma
      bus.peek(0xdf00)
      expect(reu.irq?).to be(false)
    end

    it "stays off unless enabled" do
      transfer(0x90)
      run_dma
      expect(reu.irq?).to be(false)
    end

    it "fires when enabled over an ended block" do
      transfer(0x90)
      run_dma
      bus.poke(0xdf09, 0xc0)
      expect(reu.irq?).to be(true)
    end

    it "fires on a verify error when enabled" do
      bus.poke(0xdf09, 0xa0)
      reu.ram_poke(0x020000, 0x99)
      bus.poke(0x1000, 0x00)
      transfer!(0x93)
      expect(reu.irq?).to be(true)
    end
  end

  it "powers on with the pattern a 1764 shows" do
    expect([0x0000, 0x0001, 0x0003, 0x0100, 0x2a00, 0x020000].map { |a| reu.ram_peek(a) })
      .to eq([0xff, 0x00, 0xff, 0x00, 0x00, 0x00])
  end

  it "rejects a size no REU came in" do
    expect { Badline::Computer.new(reu: 64) }.to raise_error(ArgumentError)
  end

  it "goes back to its power-on registers on reset" do
    transfer(0x90)
    reu.reset!
    expect([bus.peek(0xdf01), bus.peek(0xdf02), bus.peek(0xdf07), reu.dma?]).to eq([0x10, 0x00, 0xff, false])
  end

  describe "in a computer" do
    let(:computer) { Badline::Computer.new(reu: 512) }
    let(:bus) { computer.address_bus }

    # LDA #$90, STA $DF01 at $C000, then NOPs.
    before do
      computer.ram.write(0xc000, [0xa9, 0x90, 0x8d, 0x01, 0xdf] + ([0xea] * 16))
      computer.cpu.program_counter = 0xc000
    end

    it "halts the CPU while the transfer runs" do
      transfer(0x00)
      6.times { computer.cycle! }
      cycles = computer.cpu.cycles
      8.times { computer.cycle! }
      expect([computer.cpu.cycles - cycles, bus.peek(0xdf02)]).to eq([4, 0x04])
    end

    it "raises the CPU's IRQ line" do
      bus.poke(0xdf09, 0xc0)
      transfer(0x00, length: 1)
      10.times { computer.cycle! }
      expect(computer.cpu.irq).to be(true)
    end

    # Pinned by REU/rmw-trigger/rmwtrigger-ram.
    it "takes the bus from an INC of $FF00 before its second write" do
      computer.ram.write(0xc000, [0xee, 0x00, 0xff])
      transfer(0x80, length: 1)
      12.times { computer.cycle! }
      expect(computer.ram.peek(0xff00)).to eq(bus.kernal_rom.peek(0xff00))
    end

    # Pinned by REU/bonzai/spritetiming.
    it "misses BA falling for sprite 0 on the line its DMA starts" do
      bus.poke(0xd015, 0x01)
      bus.poke(0xd001, 0x40)
      computer.cycle! until computer.vic.rasterline == 0x40 && computer.vic.column == 54
      expect([computer.vic.ba_low?, computer.vic.reu_ba_late?]).to eq([true, true])
    end

    it "sees BA for sprite 0 on the lines after" do
      bus.poke(0xd015, 0x01)
      bus.poke(0xd001, 0x40)
      computer.cycle! until computer.vic.rasterline == 0x41 && computer.vic.column == 54
      expect(computer.vic.reu_ba_late?).to be(false)
    end

    # Pinned by REU/reutiming2/e4-m2.
    it "sees a bad line's DMA end where sprite 0's follows it" do
      bus.poke(0xd015, 0x01)
      bus.poke(0xd001, 0x31)
      bus.poke(0xd011, 0x1b)
      computer.cycle! until computer.vic.rasterline == 0x33 && computer.vic.column == 54
      expect([computer.vic.ba_low?, computer.vic.reu_ba_handed_on?]).to eq([true, true])
    end

    it "is reset with the machine" do
      transfer(0x80)
      computer.reset!
      expect(bus.peek(0xdf01)).to eq(0x10)
    end
  end
end
