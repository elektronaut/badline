# frozen_string_literal: true

require "badline/chips/m6809"

# 64K of RAM for a Badline::Chips::M6809, which logs each access as the
# cycle it falls on, "r" or "w", and its address.
class M6809Bus
  attr_reader :ram, :accesses
  attr_writer :cpu

  def initialize
    @ram = Array.new(0x10000, 0)
    @accesses = []
  end

  # Stores +bytes+ from +address+ on.
  def load(address, *bytes)
    bytes.each_with_index { |byte, i| @ram[address + i] = byte }
  end

  def read(address)
    @accesses << [@cpu.cycles, "r", address]
    @ram[address]
  end

  def write(address, value)
    @accesses << [@cpu.cycles, "w", address]
    @ram[address] = value
  end

  # The accesses from cycle +from+ on, as "r:ffff" or "w:01ff", and "-"
  # for a cycle without one.
  def trace(from, to)
    (from...to).map do |cycle|
      access = @accesses.find { |at, _, _| at == cycle }
      access ? format("%<kind>s:%<address>04x", kind: access[1], address: access[2]) : "-"
    end
  end
end
