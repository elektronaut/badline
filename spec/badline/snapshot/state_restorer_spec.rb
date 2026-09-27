# frozen_string_literal: true

require "spec_helper"

describe Badline::Snapshot::StateRestorer do
  # A stand-in for a machine part: any class under Badline's namespace is
  # machine state.
  before do
    stub_const("Badline::SnapshotPart", Class.new do
      attr_accessor :a, :b, :c

      def initialize(first = nil, second = nil, third = nil)
        @a = first
        @b = second
        @c = third
      end
    end)
  end

  let(:part) { Badline::SnapshotPart }

  def round_trip(source, target = part.new)
    records = Badline::Snapshot::StateReader.decode(Badline::Snapshot::StateWriter.encode(source))
    described_class.new(records).restore(target)
  end

  it "restores plain values" do
    restored = round_trip(part.new([1, -70_000, 2**70, 1.5, :sym, nil, true, false], "text".dup, 1..3))
    expect([restored.a, restored.b, restored.c]).to eq([[1, -70_000, 2**70, 1.5, :sym, nil, true, false], "text", 1..3])
  end

  it "packs byte and word arrays" do
    restored = round_trip(part.new(Array.new(300) { |i| i & 0xff }, Array.new(300) { |i| i * 1000 }))
    expect([restored.a.sum, restored.b.last]).to eq([Array.new(300) { |i| i & 0xff }.sum, 299_000])
  end

  it "keeps shared objects shared" do
    shared = [1, 2]
    restored = round_trip(part.new(shared, shared))
    expect(restored.a).to equal(restored.b)
  end

  it "restores cycles" do
    source = part.new
    source.a = source
    expect(round_trip(source).a).to be_a(part)
  end

  it "fills the target's own objects" do
    target = part.new([0])
    array = target.a
    round_trip(part.new([7, 8]), target)
    expect(target.a).to equal(array).and eq([7, 8])
  end

  it "points at the running process's own tables" do
    expect(round_trip(part.new(Badline::CPU::FETCH_PLAN)).a).to equal(Badline::CPU::FETCH_PLAN)
  end

  it "keeps the target's host objects" do
    io = $stdout
    expect(round_trip(part.new(Object.new), part.new(io)).a).to equal(io)
  end

  def reader(object) = -> { object.a }

  it "keeps the target's callback, and restores the objects it holds" do
    source_part = part.new(5)
    target_part = part.new(0)
    callback = reader(target_part)
    round_trip(part.new(reader(source_part), source_part), part.new(callback, target_part))
    expect(callback.call).to eq(5)
  end

  it "drops a callback the target has no match for" do
    expect(round_trip(part.new([-> {}])).a).to eq([])
  end

  it "restores frozen arrays frozen" do
    expect(round_trip(part.new([1, [2].freeze].freeze)).a).to be_frozen
  end

  it "restores identity hashes" do
    key = [1]
    restored = round_trip(part.new({}.compare_by_identity.tap { |hash| hash[key] = 2 }))
    expect(restored.a).to be_compare_by_identity
  end

  it "resets a variable the snapshot's object hadn't set" do
    target = part.new
    target.instance_variable_set(:@extra, 1)
    expect(round_trip(part.new, target).instance_variable_get(:@extra)).to be_nil
  end

  def records(*ivars, extra: [])
    [Badline::Snapshot::StateReader::ObjectRecord.new(class_name: "Badline::SnapshotPart", ivars:), *extra]
  end

  it "refuses a class outside the machine" do
    file = Badline::Snapshot::StateReader::ObjectRecord.new(class_name: "File", ivars: [])
    restorer = described_class.new(records([:@a, Badline::Snapshot::Value::Ref.new(id: 1)], extra: [file]))
    expect { restorer.restore(part.new) }.to raise_error(Badline::Snapshot::FormatError, /isn't part of the machine/)
  end

  it "refuses a table this badline doesn't have" do
    restorer = described_class.new(records([:@a, Badline::Snapshot::Value::Constant.new(path: "Badline::NOPE")]))
    expect { restorer.restore(part.new) }.to raise_error(Badline::Snapshot::FormatError, /NOPE/)
  end

  it "refuses damaged machine state" do
    expect { Badline::Snapshot::StateReader.decode("\x09".b) }.to raise_error(Badline::Snapshot::FormatError)
  end
end
