# frozen_string_literal: true

# Runs neetandev/m6809's cases, converted by spinel/convert_m6809.rb,
# against the 6809 and checks registers, cycles, the bus on every cycle
# and RAM. Builds with Spinel as well as running on CRuby:
#
#   ruby -Ilib spinel/convert_m6809.rb 100 tmp/spinel/m6809_cases.txt
#   ruby --yjit -Ilib spinel/m6809_tests.rb tmp/spinel/m6809_cases.txt [repeat]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/m6809_tests.rb -o tmp/spinel/m6809_tests

require "badline/chips/m6809/core"

module M6809Tests
  NONE = 0
  READ = 1
  WRITE = 2

  # 64K of RAM, which logs each access as three numbers: the cycle, its
  # kind and its address, and the value.
  class RecordingBus
    attr_reader :log, :ram
    attr_accessor :cpu

    def initialize
      @ram = Array.new(0x10000, 0)
      @log = []
      @cpu = nil
    end

    def start
      @log = []
    end

    def read(address)
      value = @ram[address]
      record(READ, address, value)
      value
    end

    def write(address, value)
      @ram[address] = value
      record(WRITE, address, value)
    end

    private

    def record(kind, address, value)
      @log << @cpu.cycles
      @log << kind
      @log << address
      @log << value
    end
  end

  # The 6809 core on a RecordingBus.
  class CPU
    include Badline::Chips::M6809::Core
  end

  # One case: the registers in convert_m6809.rb's order and RAM before,
  # then the registers, RAM and each cycle's kind, address and data
  # after.
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

    def run(bus)
      fill(bus.ram, @ram)
      bus.start
      cpu = start(bus)
      cpu.step!
      errors = register_errors(cpu)
      errors << "cycles" if cpu.cycles * 3 != @trace.length
      errors << "trace" unless trace_matches?(bus.log)
      errors << "ram" unless ram_matches?(bus.ram)
      clear(bus.ram, @ram)
      clear(bus.ram, @memory)
      errors
    end

    private

    def ints(line)
      line[2..].split.map(&:to_i)
    end

    def start(bus)
      cpu = CPU.new(bus)
      bus.cpu = cpu
      cpu.pc = @initial[0]
      cpu.s = @initial[1]
      cpu.u = @initial[2]
      cpu.x = @initial[3]
      cpu.y = @initial[4]
      cpu.dp = @initial[5]
      cpu.a = @initial[6]
      cpu.b = @initial[7]
      cpu.cc = @initial[8]
      cpu.resume(0)
      cpu
    end

    def register_errors(cpu)
      actual = [cpu.pc, cpu.s, cpu.u, cpu.x, cpu.y, cpu.dp, cpu.a, cpu.b, cpu.cc]
      names = %w[pc s u x y dp a b cc]
      errors = []
      i = 0
      while i < actual.length
        errors << names[i] if actual[i] != @final[i]
        i += 1
      end
      errors
    end

    # Each cycle's access from the log against the trace. A cycle without
    # one is NONE.
    def trace_matches?(log)
      cycles = @trace.length / 3
      kinds = Array.new(cycles, NONE)
      addresses = Array.new(cycles, 0)
      values = Array.new(cycles, 0)
      i = 0
      while i < log.length
        cycle = log[i]
        if cycle < cycles
          kinds[cycle] = log[i + 1]
          addresses[cycle] = log[i + 2]
          values[cycle] = log[i + 3]
        end
        i += 4
      end
      cycle_matches?(kinds, addresses, values)
    end

    def cycle_matches?(kinds, addresses, values)
      cycle = 0
      while cycle < kinds.length
        kind = @trace[cycle * 3]
        data = @trace[(cycle * 3) + 2]
        return false if kinds[cycle] != kind
        return false if kind != NONE && addresses[cycle] != @trace[(cycle * 3) + 1]
        return false if kind != NONE && data >= 0 && values[cycle] != data

        cycle += 1
      end
      true
    end

    def ram_matches?(ram)
      i = 0
      while i < @memory.length
        return false if ram[@memory[i]] != @memory[i + 1]

        i += 2
      end
      true
    end

    def fill(ram, list)
      i = 0
      while i < list.length
        ram[list[i]] = list[i + 1]
        i += 2
      end
    end

    def clear(ram, list)
      i = 0
      while i < list.length
        ram[list[i]] = 0
        i += 2
      end
    end
  end
end

path = ARGV[0] || "tmp/spinel/m6809_cases.txt"
repeat = (ARGV[1] || "1").to_i
lines = File.read(path).split("\n")
cases = []
j = 0
while j < lines.length
  cases << M6809Tests::StepCase.new(lines[j][2..], lines[j + 1, 5])
  j += 6
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
passed = 0
failed = 0
checksum = 0
bus = M6809Tests::RecordingBus.new
r = 0
while r < repeat
  j = 0
  while j < cases.length
    errors = cases[j].run(bus)
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
