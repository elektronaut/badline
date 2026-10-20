# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"
require "badline/support"
require "badline/support/vic20_checkpoint"
require_relative "../../../support/xvic_snapshots"

describe Badline::Snapshot::Vice::Vic20 do
  # 8,000 cycles on, the beam is inside the text window on either model.
  def machine(ram: :unexpanded, model: "pal", cycles: 8_000) = XvicSnapshots.probing(ram, model, cycles).load

  def exported(computer) = XvicSnapshots.exported(computer)

  def container(**) = exported(machine(**))

  def loaded(container) = Badline::Snapshot::Image.new(container).load { |_line| nil }

  def sizes(container) = container.sections.to_h { |section| [section.to_s, section.data.bytesize] }

  def vic_bytes(container, offset, count) = container["VIC-I"].data.byteslice(offset, count).bytes

  describe ".export" do
    it "writes the modules xvic needs, in its order" do
      expect(container.sections.map(&:name))
        .to eq(%w[MAINCPU VIC20MEM VIC20CART VIC-I VIA1 VIA2 FSDRIVE TAPEPORT JOYPORT0 JOYSTICK0 USERPORT])
    end

    it "writes each module at the version and size xvic 3.10 writes for a PAL VIC-20" do
      expect(sizes(container).first(6)).to eq([["MAINCPU 1.4", 83], ["VIC20MEM 1.1", 5124], ["VIC20CART 2.1", 5],
                                               ["VIC-I 0.4", 1_042_678], ["VIA1 2.2", 28], ["VIA2 2.2", 28]])
    end

    it "writes the 6560's picture size" do
      expect(sizes(container(model: "ntsc"))["VIC-I 0.4"]).to eq(818_294)
    end

    it "writes every block's RAM after the internal 5K, the 3K first" do
      computer = machine(ram: :all)
      { 0x0400 => 0x11, 0x2000 => 0x22, 0xa000 => 0x55 }.each { |address, value| computer.poke(address, value) }
      memory = exported(computer)["VIC20MEM"].data.bytes
      expect([memory.length, memory[0], memory[4 + 0x1400], memory[4 + 0x2000], memory[4 + 0x8000]])
        .to eq([40_964, 0x2f, 0x11, 0x22, 0x55])
    end

    it "writes the registers after the colour RAM" do
      expect(vic_bytes(container, 0x452, 16)).to eq(XvicSnapshots::WINDOW)
    end

    it "writes the beam where xvic keeps it" do
      computer = machine
      vic = computer.vic
      expect(vic_bytes(exported(computer), 0x10, 3)).to eq([vic.column, vic.rasterline & 0xff, vic.rasterline >> 8])
    end

    it "marks the 6560's interlaced frame and its long field" do
      expect(vic_bytes(exported(interlaced), 0, 8)).to eq([1, 0, 0, 0, 0, 0, 0, 0])
    end

    it "says the file is in snapshot format 3.1, as xvic's are" do
      expect(container.to_s.byteslice(19, 2).bytes).to eq([3, 1])
    end
  end

  # The NTSC VIC-20 near the end of the first field of an interlaced
  # frame, the long one, at an instruction boundary.
  def interlaced
    computer = machine(model: "ntsc", cycles: 15_000).tap { |vic20| vic20.poke(0x9000, 0x8c) }
    vic = computer.vic
    computer.cycle! until vic.rasterline.zero?
    computer.cycle! until vic.rasterline == 258
    computer.tap { computer.cycle! until computer.cpu.boundary? }
  end

  def checkpoint(computer) = Badline::Support::Vic20Checkpoint.take(computer).to_s.sub(/display=\h+/, "")

  describe ".setup" do
    it "builds the model the picture's size says and the RAM the blocks say" do
      expect(described_class.setup(container(ram: :"8k", model: "ntsc")))
        .to eq(Badline::Snapshot::Vic20Setup.new(ram: :"8k", model: "ntsc"))
    end

    it "refuses blocks that make no RAM expansion badline fits" do
      memory = container["VIC20MEM"]
      odd = memory.with(data: memory.data.dup.tap { |data| data.setbyte(0, 0x09) })
      broken = Badline::Snapshot::Container.new([odd], machine: Badline::Snapshot::Container::VIC20)
      expect { described_class.setup(broken) }.to raise_error(Badline::Snapshot::FormatError, /blocks/)
    end
  end

  describe "a load from xvic's modules" do
    it "restores the CPU, the RAM, the VIC and the VIAs" do
      computer = machine
      expect(checkpoint(loaded(exported(computer)))).to eq(checkpoint(computer))
    end

    it "runs on alike" do
      computer = machine
      restored = loaded(exported(computer))
      [computer, restored].each { |vic20| 3_000.times { vic20.cycle! } }
      expect(checkpoint(restored)).to eq(checkpoint(computer))
    end

    it "runs on alike into the 6560's short field" do
      computer = interlaced
      restored = loaded(exported(computer))
      [computer, restored].each { |vic20| 3_000.times { vic20.cycle! } }
      expect([restored.vic.rasterline, restored.vic.column, checkpoint(restored)])
        .to eq([computer.vic.rasterline, computer.vic.column, checkpoint(computer)])
    end

    it "refuses to restore into another family" do
      expect { described_class::Restore.import(container, Struct.new(:family).new(:c64)) }
        .to raise_error(Badline::Snapshot::FormatError, /VIC-20, not a C64/)
    end
  end
end
