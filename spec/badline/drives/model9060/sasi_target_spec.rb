# frozen_string_literal: true

require "spec_helper"
require "badline/drives/model9060/sasi_target"

describe Badline::Drives::Model9060::SASITarget do
  subject(:target) { described_class.new(disk) }

  # A D9060 of 19,584 blocks, each filled with its LBA's low byte until
  # written.
  let(:disk_class) do
    Class.new do
      attr_reader :written
      attr_accessor :read_only

      def initialize = @written = {}
      def block_count = 19_584
      def blocks?(lba, count) = lba >= 0 && lba + count <= block_count
      def read_blocks(lba, count) = (lba...(lba + count)).flat_map { |block| block_at(block) }
      def block_at(block) = @written.fetch(block) { Array.new(256, block & 0xff) }

      def write_blocks(lba, data)
        raise Badline::Storage::WriteError, 26 if read_only

        data.each_slice(256).with_index { |bytes, i| @written[lba + i] = bytes }
      end
    end
  end

  let(:disk) { disk_class.new }

  # Runs a command from selection to bus free as the host does, answering
  # each REQ, and returns the bytes the controller sent in each phase and
  # the cycles it took.
  def transact(command, out = [])
    target.select(0x01)
    sent = Hash.new { |hash, phase| hash[phase] = [] }
    command = command.dup
    out = out.dup
    sent[:cycles] = [0]
    while target.busy?
      sent[:cycles][0] += wait_for_request
      byte = target.phase == described_class::COMMAND ? command.shift : out.shift
      sent[target.phase] << target.data if target.input?
      target.acknowledge(byte || 0)
    end
    sent
  end

  # Clocks the controller until it raises REQ, and returns the cycles that
  # took.
  def wait_for_request
    cycles = 0
    until target.request?
      target.clock
      cycles += 1
    end
    cycles
  end

  def request_after_a_cycle?
    target.clock
    target.request?
  end

  def status_and_message(command) = transact(command).values_at(described_class::STATUS, described_class::MESSAGE)

  def read(lba) = [0x08, lba >> 16, (lba >> 8) & 0xff, lba & 0xff, 1, 0]

  describe "#select" do
    it "answers SEL with bit 0 on the bus with BSY" do
      target.select(0x01)
      expect(target).to be_busy
    end

    it "leaves SEL for another ID alone" do
      target.select(0x02)
      expect(target).not_to be_busy
    end
  end

  describe "the command phase" do
    before { target.select(0x01) }

    it "raises C/D with I/O low, and REQ a cycle later" do
      states = [target.request?, request_after_a_cycle?]
      expect([target.control?, target.input?, target.message?, *states]).to eq([true, false, false, false, true])
    end

    it "drops REQ on ACK and raises it again a cycle later" do
      wait_for_request
      target.acknowledge(0)
      expect([target.request?, request_after_a_cycle?]).to eq([false, true])
    end
  end

  describe "Test Unit Ready" do
    it "ends with good status and a zero message" do
      expect(status_and_message([0, 0, 0, 0, 1, 0])).to eq([[0], [0]])
    end

    it "frees the bus after the message" do
      transact([0, 0, 0, 0, 1, 0])
      expect([target.busy?, target.phase]).to eq([false, described_class::BUS_FREE])
    end

    it "fails as DRIVE NOT READY with no disk" do
      target.disk = nil
      expect(status_and_message([0, 0, 0, 0, 1, 0])).to eq([[2], [0x04]])
    end

    it "fails as DRIVE NOT READY for drive 1" do
      expect(status_and_message([0, 0x20, 0, 0, 1, 0])).to eq([[2], [0x04]])
    end
  end

  describe "Read" do
    it "sends the block's 256 bytes with I/O high and C/D low" do
      expect(transact(read(300))[described_class::DATA_IN]).to eq(Array.new(256, 300 & 0xff))
    end

    it "sends as many blocks as the command counts" do
      blocks = transact([0x08, 0, 0, 10, 3, 0])[described_class::DATA_IN].each_slice(256)
      expect(blocks.map(&:first)).to eq([10, 11, 12])
    end

    it "fails past the disk's end as an illegal address, with the LBA valid" do
      expect(status_and_message(read(19_584))).to eq([[2], [0xa1]])
    end

    it "takes no longer than a turn and a block on the cylinder it's on" do
      expect(transact(read(5))[:cycles].first).to be_between(521, (33 * 521) + 10)
    end
  end

  describe "Request Sense" do
    it "sends the last command's error and its LBA" do
      transact(read(0x12345))
      expect(transact([0x03, 0, 0, 0, 0, 0])[described_class::DATA_IN]).to eq([0xa1, 0x01, 0x23, 0x45])
    end

    it "sends zeros after a command that went well" do
      transact(read(1))
      expect(transact([0x03, 0, 0, 0, 0, 0])[described_class::DATA_IN]).to eq([0, 0, 0, 0])
    end
  end

  describe "Write" do
    let(:data) { Array.new(256) { |i| i ^ 0x5a } }

    it "writes the block the host sent" do
      transact([0x0a, 0, 0x10, 0, 1, 0], data)
      expect(disk.read_blocks(0x1000, 1)).to eq(data)
    end

    it "ends with good status" do
      expect(transact([0x0a, 0, 0x10, 0, 1, 0], data)[described_class::STATUS]).to eq([0])
    end

    it "fails as a write fault on a disk that takes no writes" do
      disk.read_only = true
      expect(transact([0x0a, 0, 0, 1, 1, 0], data).values_at(described_class::STATUS, described_class::MESSAGE))
        .to eq([[2], [0x03]])
    end
  end

  describe "Seek" do
    it "takes 3 ms a cylinder and 15 ms to settle" do
      expect(transact([0x0b, 0, 10 * 128 / 256, (10 * 128) & 0xff, 0, 0xc0])[:cycles].first)
        .to be_between(45_000, 45_020)
    end

    it "moves the heads to the cylinder" do
      transact([0x0b, 0, 0x14, 0, 0, 0xc0])
      expect(target.cylinder).to eq(40)
    end

    it "takes Recalibrate back to cylinder 0" do
      transact([0x0b, 0, 0x14, 0, 0, 0xc0])
      expect(transact([0x01, 0, 0, 0, 0, 0xc0])[:cycles].first).to be_between(135_000, 135_020)
    end
  end

  describe "the geometry command, $C0" do
    before { transact([0xc0, 0x04, 0, 152, 5, 31]) }

    it "takes the last head and sector a D9090's DOS sends" do
      expect([target.heads, target.sectors]).to eq([6, 32])
    end

    it "places a block's cylinder by the heads it set" do
      transact([0x0b, 0, 0x1e, 0, 0, 0xc0])
      expect(target.cylinder).to eq(40)
    end
  end

  describe "Format Unit" do
    before { transact([0x04, 0, 0, 0, 1, 0xc0]) }

    it "erases the disk" do
      expect([disk.written.length, disk.written.values.uniq]).to eq([19_584, [Array.new(256, 0)]])
    end

    it "lets the passes after it seek and read with no delay but a cycle a byte" do
      expect(transact(read(19_000))[:cycles].first).to eq(6 + 256 + 2)
    end

    it "ends the fast mode at another command" do
      transact([0, 0, 0, 0, 1, 0])
      expect(target).not_to be_fast
    end
  end

  describe "the vendor commands" do
    it "reads back the block buffer $0E wrote with $0C" do
      transact([0x0e, 0, 0, 0, 0, 0xc0], (0...256).to_a)
      expect(transact([0x0c, 0, 0, 0, 0, 0xc0])[described_class::DATA_IN]).to eq((0...256).to_a)
    end

    it "keeps the last block read in the buffer" do
      transact(read(7))
      expect(transact([0x0c, 0, 0, 0, 0, 0xc0])[described_class::DATA_IN]).to eq(Array.new(256, 7))
    end

    it "sends four bytes for $E3" do
      expect(transact([0xe3, 0, 0, 0, 0, 0])[described_class::DATA_IN]).to eq([0, 0, 0, 0])
    end
  end

  it "fails a command it doesn't know as invalid" do
    expect(status_and_message([0x15, 0, 0, 0, 0, 0])).to eq([[2], [0x20]])
  end

  describe "#reset" do
    it "frees the bus in the middle of a command" do
      target.select(0x01)
      target.reset
      expect(target).not_to be_busy
    end
  end

  describe "#quiet?" do
    before do
      target.select(0x01)
      [0x0b, 0, 0x14, 0, 0, 0xc0].each do |byte|
        wait_for_request
        target.acknowledge(byte)
      end
    end

    it "is false while a seek counts down" do
      expect(target).not_to be_quiet
    end

    it "is true once the status is up" do
      wait_for_request
      expect(target).to be_quiet
    end
  end
end
