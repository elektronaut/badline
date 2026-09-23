# frozen_string_literal: true

# Runs SingleStepTests cases, converted by spinel/convert.rb, against the
# CPU and checks registers, cycle count, the bus trace and RAM. Builds
# with Spinel as well as running on CRuby:
#
#   ruby -Ilib spinel/convert.rb 100 tmp/spinel/cases.txt
#   ruby --yjit -Ilib spinel/cpu_tests.rb tmp/spinel/cases.txt [repeat]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/cpu_tests.rb -o tmp/spinel/cpu_tests

require "badline/integer_helper"
require "badline/addressable"
require "badline/memory"
require "badline/instruction"
require "badline/instruction_set"
require "badline/status"
require "badline/interrupts"
require "badline/traps"
require "badline/cpu"

module CPUTests
  class RecordingMemory < Badline::Memory
    attr_reader :accesses

    def initialize
      super
      @accesses = []
      @logging = false
    end

    def reset_log!
      @accesses = []
      @logging = true
    end

    def stop_log!
      @logging = false
    end

    def peek(addr)
      value = super
      record(addr, value, 0)
      value
    end

    def poke(addr, value)
      record(addr, value, 1)
      super
    end

    private

    def record(addr, value, kind)
      return unless @logging

      @accesses << addr
      @accesses << value
      @accesses << kind
    end
  end

  # One test: initial registers and RAM, expected registers and RAM, and the
  # expected bus trace as address, value, kind (0 read, 1 write) triples.
  class StepCase
    attr_reader :name

    def initialize(name, lines)
      @name = name
      @initial = ints(lines[0])
      @ram = ints(lines[1])
      @final = ints(lines[2])
      @memory = ints(lines[3])
      @trace = ints(lines[4])
    end

    def run(memory)
      cpu = start(memory)
      memory.reset_log!
      cpu.step!
      cpu.cycle! while cpu.jammed? && cpu.cycles < expected_cycles
      errors = register_errors(cpu) + bus_errors(cpu, memory)
      memory.stop_log!
      clear(memory, @ram)
      clear(memory, @memory)
      errors
    end

    private

    def ints(line)
      line[2..].split.map(&:to_i)
    end

    def expected_cycles
      @trace.length / 3
    end

    def start(memory)
      cpu = Badline::CPU.new(memory, ane_constant: 0xee)
      cpu.program_counter = @initial[0]
      cpu.stack_pointer = @initial[1]
      cpu.a = @initial[2]
      cpu.x = @initial[3]
      cpu.y = @initial[4]
      cpu.p = @initial[5]
      fill(memory, @ram)
      cpu
    end

    def register_errors(cpu)
      errors = []
      errors << "pc" if cpu.program_counter != @final[0]
      errors << "s" if cpu.stack_pointer != @final[1]
      errors << "a" if cpu.a != @final[2]
      errors << "x" if cpu.x != @final[3]
      errors << "y" if cpu.y != @final[4]
      errors << "p" if cpu.p != (@final[5] | 0x20)
      errors
    end

    def bus_errors(cpu, memory)
      errors = []
      errors << "cycles" if cpu.cycles != expected_cycles
      errors << "reads" if accesses_of(memory.accesses, 0) != accesses_of(@trace, 0)
      errors << "writes" if accesses_of(memory.accesses, 1) != accesses_of(@trace, 1)
      errors << "ram" unless ram_matches?(memory)
      errors
    end

    def ram_matches?(memory)
      i = 0
      while i < @memory.length
        return false if memory.peek(@memory[i]) != @memory[i + 1]

        i += 2
      end
      true
    end

    def accesses_of(list, kind)
      out = []
      i = 0
      while i < list.length
        if list[i + 2] == kind
          out << list[i]
          out << list[i + 1]
        end
        i += 3
      end
      out
    end

    def fill(memory, list)
      i = 0
      while i < list.length
        memory.poke(list[i], list[i + 1])
        i += 2
      end
    end

    def clear(memory, list)
      i = 0
      while i < list.length
        memory.poke(list[i], 0)
        i += 2
      end
    end
  end
end

path = ARGV[0] || "tmp/spinel/cases.txt"
repeat = (ARGV[1] || "1").to_i
lines = File.read(path).split("\n")
cases = []
j = 0
while j < lines.length
  cases << CPUTests::StepCase.new(lines[j][2..], lines[j + 1, 5])
  j += 6
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
passed = 0
failed = 0
checksum = 0
memory = CPUTests::RecordingMemory.new
r = 0
while r < repeat
  j = 0
  while j < cases.length
    errors = cases[j].run(memory)
    if errors.empty?
      passed += 1
    else
      failed += 1
      puts "FAIL #{cases[j].name}: #{errors.join(',')}" if r.zero?
    end
    checksum = ((checksum * 31) + errors.length + j) % 1_000_000_007
    j += 1
  end
  r += 1
end
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
puts "passed #{passed} failed #{failed} checksum #{checksum}"
puts "elapsed #{(elapsed * 1000).round} ms"
