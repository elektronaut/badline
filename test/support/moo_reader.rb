# frozen_string_literal: true

require "zlib"

# Reads the SingleStepTests MOO format, gzipped or not: a "MOO " header
# chunk with the version, the case count and the CPU's name, then a
# "TEST" chunk per case. Every chunk is a four-byte tag, a little-endian
# 32-bit length and that many bytes. A case holds its NAME, the
# instruction's BYTS, its INIT and FINA states (REGS: a 16-bit mask, then
# a 16-bit word for each register the mask names, in the order the reader
# is given; RAM: a count of 32-bit address and 8-bit value pairs), and the
# CYCL list: per cycle a pin byte, a 16-bit address, a data byte and a
# four-letter status.
class MOOReader
  Case = Struct.new(:index, :name, :bytes, :initial, :final, :cycles)
  State = Struct.new(:registers, :ram)
  Cycle = Struct.new(:pins, :address, :data, :status)

  class FormatError < StandardError; end

  attr_reader :version, :count, :cpu

  def self.open(path, registers) = new(File.binread(path), registers)

  def initialize(data, registers)
    @data = data.start_with?("\x1f\x8b".b) ? Zlib.gunzip(data) : data.b
    @registers = registers
    tag, body, @start = chunk(@data, 0)
    raise FormatError, "not a MOO file" unless tag == "MOO "

    @version = body.unpack("CC")
    @count = body.unpack1("V", offset: 4)
    @cpu = body[8, 4].delete("\0 ")
  end

  # Yields each case, or returns an enumerator over them.
  def each
    return enum_for(:each) unless block_given?

    position = @start
    while position < @data.bytesize
      tag, body, position = chunk(@data, position)
      yield parse_case(body) if tag == "TEST"
    end
  end

  include Enumerable

  # The number of TEST chunks the file holds, which a whole file has as
  # many of as its header counts.
  def chunks
    found = 0
    position = @start
    while position < @data.bytesize
      tag, _, position = chunk(@data, position)
      found += 1 if tag == "TEST"
    end
    found
  end

  private

  def chunk(data, position)
    tag = data.byteslice(position, 4)
    length = data.unpack1("V", offset: position + 4)
    raise FormatError, "chunk #{tag.inspect} at #{position} runs past the end" if position + 8 + length > data.bytesize

    [tag, data.byteslice(position + 8, length), position + 8 + length]
  end

  def subchunks(body)
    found = {}
    position = 0
    while position < body.bytesize
      tag, inner, position = chunk(body, position)
      found[tag] = inner
    end
    found
  end

  def parse_case(body)
    index = body.unpack1("V")
    parts = subchunks(body.byteslice(4..))
    Case.new(index, counted(parts.fetch("NAME")), counted(parts.fetch("BYTS")).bytes,
             state(parts.fetch("INIT")), state(parts.fetch("FINA")), cycles(parts.fetch("CYCL")))
  end

  def counted(body) = body.byteslice(4, body.unpack1("V"))

  def state(body)
    parts = subchunks(body)
    State.new(registers(parts.fetch("REGS")), ram(parts.fetch("RAM ")))
  end

  def registers(body)
    mask = body.unpack1("v")
    words = body.byteslice(2..).unpack("v*")
    @registers.each_with_index.with_object({}) do |(name, bit), found|
      found[name] = words.shift if mask[bit] == 1
    end
  end

  def ram(body)
    body.byteslice(4, body.unpack1("V") * 5).unpack("VC" * body.unpack1("V")).each_slice(2).to_a
  end

  def cycles(body)
    body.byteslice(4, body.unpack1("V") * 8).unpack("CvCa4" * body.unpack1("V")).each_slice(4).map do |fields|
      Cycle.new(*fields)
    end
  end
end
