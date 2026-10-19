# frozen_string_literal: true

require_relative "m6809_vectors"
require_relative "m6809_divergences"

# Runs neetandev/m6809's cases against a 6809 core: one instruction from
# the initial registers and RAM, then the registers, RAM and the bus on
# every cycle against the final state, as M6809Divergences moves it to
# the documents where they and the vectors disagree. The core is any class whose new
# takes a bus answering read(address) and write(address, value), that has
# an accessor for each of M6809Vectors::REGISTERS, a resume that puts it
# at an instruction boundary, step! and cycles. A cycle without a bus
# access is one the vectors list as "----".
module M6809SingleStep
  CASES = ENV["M6809_SAMPLE"] == "all" ? nil : 100

  # A 64K RAM that records each access as the cycle it falls on, its
  # kind, address and value.
  class Bus
    attr_reader :accesses, :ram
    attr_writer :cpu

    def initialize(ram)
      @ram = Array.new(0x10000, 0)
      ram.each { |address, value| @ram[address] = value }
      @accesses = []
    end

    def read(address)
      value = @ram[address]
      @accesses << [@cpu.cycles, "r-m-", address, value]
      value
    end

    def write(address, value)
      @ram[address] = value
      @accesses << [@cpu.cycles, "-wm-", address, value]
    end

    # Each cycle's status, address and data, as the vectors list them.
    def trace(length)
      cycles = Array.new(length) { ["----", 0, 0] }
      @accesses.each { |cycle, status, address, value| cycles[cycle] = [status, address, value] if cycle < length }
      cycles
    end
  end

  module_function

  # The first CASES cases of the file, or all of them when M6809_SAMPLE
  # is all.
  def cases(path)
    cases = M6809Vectors.reader(path).each
    CASES ? cases.first(CASES) : cases.to_a
  end

  def start(test, cpu_class)
    bus = Bus.new(test.initial.ram)
    cpu = cpu_class.new(bus)
    bus.cpu = cpu
    test.initial.registers.each { |name, value| cpu.public_send("#{name}=", value) }
    cpu.resume(0)
    [cpu, bus]
  end

  # Runs one case and returns what differs, empty if it passed.
  def run(test, cpu_class)
    cpu, bus = start(test, cpu_class)
    cpu.step!
    registers = M6809Divergences.expected_registers(test)
    trace = M6809Divergences.expected_trace(test)
    errors = registers.filter_map { |name, value| mismatch(name, cpu.public_send(name), value) }
    errors << "cycles #{cpu.cycles} != #{trace.length}" if cpu.cycles != trace.length
    errors.concat(ram_errors(bus, test.final.ram))
    errors << trace_error(bus.trace(trace.length), trace)
    errors.compact
  end

  def mismatch(name, actual, expected)
    format("%<name>s $%<actual>02x != $%<expected>02x", name:, actual:, expected:) unless actual == expected
  end

  def ram_errors(bus, ram)
    ram.filter_map { |address, value| mismatch(format("ram[%04x]", address), bus.ram[address], value) }
  end

  # The first cycle that differs. A cycle expected with nil data is one
  # whose data isn't checked.
  def trace_error(actual, expected)
    index = expected.each_index.find do |i|
      status, address, data = expected[i]
      actual[i][0] != status || actual[i][1] != address || (data && actual[i][2] != data)
    end
    "cycle #{index}: #{actual[index].inspect} != #{expected[index].inspect}" if index
  end
end
