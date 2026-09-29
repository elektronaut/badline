# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/sdl"

describe Badline::LibC do
  it "allocates memory" do
    memory = described_class.malloc(16)
    described_class.free(memory)
    expect(memory).to be_a(Fiddle::Pointer)
  end

  def readable?(io)
    described_class.pollfd_fd(described_class.pollfd, io.fileno)
    described_class.pollfd_events(described_class.pollfd, described_class::POLLIN)
    described_class.poll(described_class.pollfd, 1, 0) == 1
  end

  it "polls a file descriptor" do
    IO.pipe do |reader, writer|
      writer.write("x")
      expect(readable?(reader)).to be(true)
    end
  end

  it "polls a file descriptor with nothing to read" do
    IO.pipe { |reader, _| expect(readable?(reader)).to be(false) }
  end
end
