# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "badline"

opcodes = Badline::Instruction.map.keys

TEST_CYCLES = true

# Set to nil to run all tests
SAMPLE_SIZE = 100

TESTS = opcodes.flat_map do |opcode|
  name = opcode.to_s(16).rjust(2, "0")
  tests = JSON.parse(File.read("vendor/65x02/6502/v1/#{name}.json"))
  tests = tests.sample(SAMPLE_SIZE) if SAMPLE_SIZE
  tests
end

class RecordingMemory < Badline::Memory
  attr_reader :accesses

  def reset_log!
    @accesses = []
  end

  def peek(addr)
    value = super
    @accesses << [addr, value, "read"] if @accesses
    value
  end

  def poke(addr, value)
    @accesses << [addr, value, "write"] if @accesses
    super
  end
end

class TestCPU < Minitest::Test
  include Badline::IntegerHelper

  def assert_equal_hex(expectation, actual, msg = nil)
    assert_equal(expectation.to_s(16), actual.to_s(16), msg)
  end

  def assert_memory(expectation, memory)
    expectation.each do |addr, value|
      assert_equal_hex(
        memory.peek(addr), value,
        "Wrong value in memory address #{format16(addr)}"
      )
    end
  end

  def assert_status(expected_value, actual)
    expectation = Badline::CPUStatus.new(Badline::CPU::STATUS_FLAGS,
                                         value: expected_value)

    assert_equal(expectation.carry, actual.carry, "status: carry")
    assert_equal(expectation.zero, actual.zero, "status: zero")
    assert_equal(expectation.interrupt, actual.interrupt, "status: interrupt")
    assert_equal(expectation.decimal, actual.decimal, "status: decimal")
    assert_equal(expectation.break, actual.break, "status: break")
    assert_equal(expectation.overflow, actual.overflow, "status: overflow")
    assert_equal(expectation.negative, actual.negative, "status: negative")
  end

  def assert_registers(state, cpu)
    assert_equal_hex(state["pc"], cpu.program_counter, "program counter")
    assert_equal_hex(state["s"], cpu.stack_pointer, "stack pointer")
    assert_equal_hex(state["a"], cpu.a, "A register")
    assert_equal_hex(state["x"], cpu.x, "X register")
    assert_equal_hex(state["y"], cpu.y, "Y register")
    assert_status(state["p"], cpu.status)
  end

  def assert_bus_activity(expected_cycles, accesses)
    %w[write read].each do |kind|
      assert_equal(expected_cycles.select { |c| c.last == kind },
                   accesses.select { |c| c.last == kind },
                   "Bus #{kind}s")
    end
  end

  def setup_cpu(state)
    cpu = Badline::CPU.new(RecordingMemory.new, ane_constant: 0xee)
    cpu.program_counter = state["pc"]
    cpu.stack_pointer = state["s"]
    cpu.a = state["a"]
    cpu.x = state["x"]
    cpu.y = state["y"]
    cpu.p = state["p"]
    state["ram"].each do |addr, value|
      cpu.memory.poke(addr, value)
    end
    cpu.memory.reset_log!
    cpu
  end

  TESTS.each_with_index do |test, i|
    define_method "test_#{i}_#{test['name'].gsub(' ', '_')}" do
      cpu = setup_cpu(test["initial"])
      cpu.step!
      cpu.cycle! while cpu.jammed? && cpu.cycles < test["cycles"].length

      assert_registers(test["final"], cpu)
      if TEST_CYCLES
        assert_equal(test["cycles"].length, cpu.cycles, "Cycle count")
        assert_bus_activity(test["cycles"], cpu.memory.accesses)
      end

      assert_memory(test["final"]["ram"], cpu.memory)
    end
  end
end
