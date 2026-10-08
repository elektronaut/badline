# frozen_string_literal: true

# Runs SingleStepTests' Z80 cases, converted by spinel/convert_z80.rb,
# against the Z80 and checks registers, T-states, the bus pins on each
# T-state, the ports and RAM. Builds with Spinel as well as running on
# CRuby:
#
#   ruby -Ilib spinel/convert_z80.rb 20 tmp/spinel/z80_cases.txt
#   ruby --yjit -Ilib spinel/z80_tests.rb tmp/spinel/z80_cases.txt [repeat]
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/z80_tests.rb -o tmp/spinel/z80_tests

require "badline/z80/core"

module Z80Tests
  FETCH = 0
  READ = 1
  WRITE = 2
  INPUT = 3
  OUTPUT = 4

  # The pin masks convert_z80.rb writes: RD, WR, MREQ and IORQ.
  RD = 1
  WR = 2
  MREQ = 4
  IORQ = 8

  # 64K of RAM and the bytes a case's ports read, which logs each access
  # as five numbers: the T-state it starts on, its kind, the address, the
  # value, and for an opcode fetch the refresh address.
  class RecordingBus
    attr_reader :log, :ram
    attr_accessor :cpu

    def initialize
      @ram = Array.new(0x10000, 0)
      @ports = []
      @log = []
      @cpu = nil
    end

    def start(ports)
      @ports = ports
      @log = []
    end

    def fetch(address)
      value = @ram[address]
      record(FETCH, address, value, (@cpu.i << 8) | @cpu.r)
      value
    end

    def read(address)
      value = @ram[address]
      record(READ, address, value, 0)
      value
    end

    def write(address, value)
      @ram[address] = value
      record(WRITE, address, value, 0)
    end

    def input(port)
      value = 0xff
      i = 0
      while i < @ports.length
        value = @ports[i + 1] if @ports[i] == port && @ports[i + 2].zero?
        i += 3
      end
      record(INPUT, port, value, 0)
      value
    end

    def output(port, value)
      record(OUTPUT, port, value, 0)
    end

    def acknowledge = 0xff

    private

    def record(kind, address, value, refresh)
      @log << @cpu.cycles
      @log << kind
      @log << address
      @log << value
      @log << refresh
    end
  end

  # The Z80 core on a RecordingBus.
  class CPU
    include Badline::Z80::Core
  end

  # One case: the registers in convert_z80.rb's order, RAM and ports
  # before, then the registers, RAM and the pins of each T-state after.
  class StepCase
    attr_reader :name

    def initialize(name, lines)
      @name = name
      @initial = ints(lines[0])
      @ram = ints(lines[1])
      @ports = ints(lines[2])
      @final = ints(lines[3])
      @memory = ints(lines[4])
      @pins = ints(lines[5])
    end

    def run(bus)
      fill(bus.ram, @ram)
      bus.start(@ports)
      cpu = start(bus)
      cpu.step!
      errors = register_errors(cpu)
      errors << "cycles" if cpu.cycles * 3 != @pins.length
      errors << "pins" if pins(bus.log, cpu.cycles) != @pins
      errors << "ports" if ports(bus.log) != @ports
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
      start_main(cpu, @initial)
      start_others(cpu, @initial)
      cpu
    end

    def start_main(cpu, values)
      cpu.a = values[0]
      cpu.f = values[1]
      cpu.b = values[2]
      cpu.c = values[3]
      cpu.d = values[4]
      cpu.e = values[5]
      cpu.h = values[6]
      cpu.l = values[7]
    end

    def start_others(cpu, values)
      cpu.i = values[8]
      cpu.r = values[9]
      cpu.pc = values[10]
      cpu.sp = values[11]
      cpu.ix = values[12]
      cpu.iy = values[13]
      cpu.wz = values[14]
      cpu.im = values[15]
      cpu.q = values[16]
      cpu.af_alt = values[17]
      cpu.bc_alt = values[18]
      cpu.de_alt = values[19]
      cpu.hl_alt = values[20]
      cpu.iff1 = values[21] == 1
      cpu.iff2 = values[22] == 1
      cpu.after_ei = values[23] == 1
      cpu.after_ld_a_ir = values[24] == 1
    end

    def registers(cpu)
      [cpu.a, cpu.f, cpu.b, cpu.c, cpu.d, cpu.e, cpu.h, cpu.l, cpu.i, cpu.r, cpu.pc, cpu.sp, cpu.ix, cpu.iy,
       cpu.wz, cpu.im, cpu.q, cpu.af_alt, cpu.bc_alt, cpu.de_alt, cpu.hl_alt, flag(cpu.iff1), flag(cpu.iff2),
       flag(cpu.after_ei), flag(cpu.after_ld_a_ir)]
    end

    def flag(set)
      set ? 1 : 0
    end

    def register_errors(cpu)
      actual = registers(cpu)
      names = %w[a f b c d e h l i r pc sp ix iy wz im q af_ bc_ de_ hl_ iff1 iff2 ei p]
      errors = []
      i = 0
      while i < actual.length
        errors << names[i] if actual[i] != @final[i]
        i += 1
      end
      errors
    end

    # The pins of each T-state from the log, as SingleStepTests lists
    # them. T-states the CPU spends inside keep the last address.
    def pins(log, length)
      out = Array.new(length * 3, -1)
      flags = Array.new(length, 0)
      filled = Array.new(length, false)
      i = 0
      while i < log.length
        machine_cycle(out, flags, filled, log, i)
        i += 5
      end
      fill_internal(out, flags, filled, length)
    end

    def machine_cycle(out, flags, filled, log, index)
      start = log[index]
      kind = log[index + 1]
      address = log[index + 2]
      value = log[index + 3]
      length = kind == FETCH || kind >= INPUT ? 4 : 3
      t = 0
      while t < length && start + t < filled.length
        out[(start + t) * 3] = kind == FETCH && t >= 2 ? log[index + 4] : address
        filled[start + t] = true
        t += 1
      end
      strobe(out, flags, start, kind, value)
    end

    def strobe(out, flags, start, kind, value)
      case kind
      when FETCH, READ
        set_pin(flags, start + 1, RD | MREQ)
        set_data(out, start + 2, value)
      when WRITE
        set_pin(flags, start + 1, WR | MREQ)
        set_data(out, start + 1, value)
      when INPUT
        set_pin(flags, start + 2, RD | IORQ)
        set_data(out, start + 3, value)
      else
        set_pin(flags, start + 2, WR | IORQ)
        set_data(out, start + 2, value)
      end
    end

    def set_pin(flags, tick, mask)
      flags[tick] = mask if tick < flags.length
    end

    def set_data(out, tick, value)
      out[(tick * 3) + 1] = value if tick * 3 < out.length
    end

    def fill_internal(out, flags, filled, length)
      address = -1
      t = 0
      while t < length
        if filled[t]
          address = out[t * 3]
        else
          out[t * 3] = address
        end
        out[(t * 3) + 2] = flags[t]
        t += 1
      end
      out
    end

    def ports(log)
      out = []
      i = 0
      while i < log.length
        kind = log[i + 1]
        if kind >= INPUT
          out << log[i + 2]
          out << log[i + 3]
          out << (kind == INPUT ? 0 : 1)
        end
        i += 5
      end
      out
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

path = ARGV[0] || "tmp/spinel/z80_cases.txt"
repeat = (ARGV[1] || "1").to_i
lines = File.read(path).split("\n")
cases = []
j = 0
while j < lines.length
  cases << Z80Tests::StepCase.new(lines[j][2..], lines[j + 1, 6])
  j += 7
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
passed = 0
failed = 0
checksum = 0
bus = Z80Tests::RecordingBus.new
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
