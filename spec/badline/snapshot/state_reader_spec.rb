# frozen_string_literal: true

require "spec_helper"

describe Badline::Snapshot::StateReader do
  let(:out) do
    Badline::Snapshot::StateWriter.new.marker("TEST").int(-5).boolean(true).optional_int(nil).optional_int(7)
                                  .ints([1, 2]).booleans([false, true]).blob([0, 255]).string("path")
                                  .optional_string(nil)
  end
  let(:input) { described_class.new(out.state) }

  def read_all
    input.marker("TEST")
    [input.int, input.boolean?, input.optional_int, input.optional_int, input.ints, input.booleans, input.blob,
     input.string, input.optional_string]
  end

  it "reads back what the writer wrote, in order" do
    expect(read_all).to eq([-5, true, nil, 7, [1, 2], [false, true], [0, 255], "path", nil])
  end

  it "knows when it has read everything" do
    read_all
    expect(input).to be_finished
  end

  it "fails on a marker it doesn't find" do
    expect { input.marker("OTHER") }.to raise_error(Badline::Snapshot::FormatError, /expected OTHER/)
  end

  it "fails past the end" do
    read_all
    expect { input.int }.to raise_error(Badline::Snapshot::FormatError, /ends early/)
  end

  it "reads into an array in place" do
    array = [9, 9, 9]
    input.marker("TEST")
    5.times { input.int }
    input.ints_into(array)
    expect(array).to eq([1, 2])
  end

  it "fails on a boolean that isn't 0 or 1" do
    input.marker("TEST")
    expect { input.boolean? }.to raise_error(Badline::Snapshot::FormatError, /expected a boolean/)
  end

  it "refuses to write what isn't an Integer" do
    expect { Badline::Snapshot::StateWriter.new.int(nil) }.to raise_error(TypeError)
  end
end
