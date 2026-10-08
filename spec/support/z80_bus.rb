# frozen_string_literal: true

require "badline/z80"

# 64K of RAM for a Badline::Z80, which logs each access as its kind and
# address, and puts +vector+ on the data bus when the CPU acknowledges an
# interrupt.
class Z80Bus
  attr_reader :ram, :accesses
  attr_accessor :vector

  def initialize
    @ram = Array.new(0x10000, 0)
    @accesses = []
    @vector = 0xff
  end

  # Stores +bytes+ from +address+ on.
  def load(address, *bytes)
    bytes.each_with_index { |byte, i| @ram[address + i] = byte }
  end

  def fetch(address)
    log(:fetch, address)
    @ram[address]
  end

  def read(address)
    log(:read, address)
    @ram[address]
  end

  def write(address, value)
    log(:write, address)
    @ram[address] = value
  end

  def input(port)
    log(:input, port)
    0xff
  end

  def output(port, _value)
    log(:output, port)
  end

  def acknowledge
    log(:acknowledge, nil)
    @vector
  end

  private

  def log(kind, address) = @accesses << [kind, address]
end
