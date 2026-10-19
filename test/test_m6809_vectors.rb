# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/m6809_single_step"

# The MOO reader, the fetched neetandev/m6809 vectors, and the runner on
# a stand-in core that knows only ABX.
class TestM6809Vectors < Minitest::Test
  # ABX as the datasheet times it: the opcode, a read of the next byte and
  # a dead cycle on $FFFF.
  class ABXOnly
    attr_accessor(*M6809Vectors::REGISTERS)
    attr_reader :cycles

    def initialize(bus)
      @bus = bus
      @cycles = 0
    end

    def resume(cycles)
      @cycles = cycles
    end

    def step!
      [@pc, (@pc + 1) & 0xffff, 0xffff].each do |address|
        @bus.read(address)
        @cycles += 1
      end
      @x = (@x + @b) & 0xffff
      @pc = (@pc + 1) & 0xffff
    end
  end

  def chunk(tag, body) = tag + [body.bytesize].pack("V") + body

  def counted(bytes) = [bytes.bytesize].pack("V") + bytes

  def state(registers, ram)
    chunk("REGS", [0b1_0000_0001, *registers].pack("v*")) +
      chunk("RAM ", [ram.length].pack("V") + ram.map { |pair| pair.pack("VC") }.join)
  end

  def moo
    test = [7].pack("V") + chunk("NAME", counted("3A 0007")) + chunk("BYTS", counted("\x3a")) +
           chunk("INIT", state([0x1234, 0x40], [[0x1234, 0x3a]])) +
           chunk("FINA", state([0x1235, 0x40], [[0x1234, 0x3a]])) +
           chunk("CYCL", "#{[1, 3, 0x1234, 0x3a].pack('VCvC')}r-m-")
    chunk("MOO ", "#{[1, 1, 0, 1].pack('CCvV')}6809") + chunk("TEST", test)
  end

  def test_reads_a_case
    reader = MOOReader.new(moo, M6809Vectors::REGISTERS)
    found = reader.first

    assert_equal [[1, 1], 1, "6809", 7, "3A 0007", [0x3a], { pc: 0x1235, cc: 0x40 }, [0x1234, 0x3a, "r-m-"]],
                 [reader.version, reader.count, reader.cpu, found.index, found.name, found.bytes,
                  found.final.registers, found.cycles.first.to_a.drop(1)]
  end

  def test_refuses_a_truncated_file
    assert_raises(MOOReader::FormatError) { MOOReader.new(moo[0...-3], M6809Vectors::REGISTERS).to_a }
  end

  def test_every_file_holds_the_manifests_cases
    assert_nil M6809Vectors.check
  end

  def test_the_runner_passes_abx
    failures = M6809SingleStep.cases(M6809Vectors.path("3a")).flat_map { |test| M6809SingleStep.run(test, ABXOnly) }

    assert_empty failures
  end

  def test_the_runner_reports_a_wrong_cycle
    test = M6809SingleStep.cases(M6809Vectors.path("3a")).first
    test.cycles[2].address = 0xfffe

    assert_match(/\Acycle 2: /, M6809SingleStep.run(test, ABXOnly).join)
  end
end
