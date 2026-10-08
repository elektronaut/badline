# frozen_string_literal: true

require "json"
require "badline/z80"

# Runs SingleStepTests' Z80 cases (vendor/z80/v1) against Badline::Z80:
# one instruction from the initial state, then the registers, RAM, the
# port accesses and the bus pins on every T-state against the final state.
module Z80SingleStep
  DIR = "vendor/z80/v1"

  REGISTERS = %w[a b c d e f h l i r pc sp ix iy wz im q].freeze
  ALTERNATES = { "af_" => :af_alt, "bc_" => :bc_alt, "de_" => :de_alt, "hl_" => :hl_alt }.freeze
  LATCHES = { "iff1" => :iff1, "iff2" => :iff2, "ei" => :after_ei, "p" => :after_ld_a_ir }.freeze

  # A 64K RAM and the ports a case reads, which records each bus access
  # as the T-state it starts on, its kind, address and value, and for an
  # opcode fetch the refresh address.
  class Bus
    attr_reader :accesses, :ram
    attr_writer :cpu

    def initialize(ram, ports)
      @ram = Array.new(0x10000, 0)
      ram.each { |address, value| @ram[address] = value }
      @ports = ports.select { |_, _, kind| kind == "r" }.to_h { |port, value, _| [port, value] }
      @accesses = []
    end

    def fetch(address)
      value = @ram[address]
      @accesses << [@cpu.cycles, :fetch, address, value, (@cpu.i << 8) | @cpu.r]
      value
    end

    def read(address)
      value = @ram[address]
      @accesses << [@cpu.cycles, :read, address, value]
      value
    end

    def write(address, value)
      @ram[address] = value
      @accesses << [@cpu.cycles, :write, address, value]
    end

    def input(port)
      value = @ports.fetch(port, 0xff)
      @accesses << [@cpu.cycles, :input, port, value]
      value
    end

    def output(port, value)
      @accesses << [@cpu.cycles, :output, port, value]
    end

    def acknowledge = 0xff

    # The pins on each T-state, as SingleStepTests lists them: the address,
    # the data or nil, and the r, w, m (MREQ) and i (IORQ) lines.
    def pins(length)
      pins = Array.new(length)
      @accesses.each do |start, kind, address, value, refresh|
        machine_cycle(kind, address, value, refresh).each_with_index { |pin, i| pins[start + i] = pin }
      end
      fill_internal(pins)
    end

    def ports
      @accesses.filter_map do |_, kind, address, value|
        [address, value, kind == :input ? "r" : "w"] if %i[input output].include?(kind)
      end
    end

    private

    def machine_cycle(kind, address, value, refresh)
      case kind
      when :fetch then [[address, nil, "----"], [address, nil, "r-m-"], [refresh, value, "----"],
                        [refresh, nil, "----"]]
      when :read then [[address, nil, "----"], [address, nil, "r-m-"], [address, value, "----"]]
      when :write then [[address, nil, "----"], [address, value, "-wm-"], [address, nil, "----"]]
      when :input then [[address, nil, "----"], [address, nil, "----"], [address, nil, "r--i"],
                        [address, value, "----"]]
      else [[address, nil, "----"], [address, nil, "----"], [address, value, "-w-i"], [address, nil, "----"]]
      end
    end

    def fill_internal(pins)
      address = nil
      pins.map do |pin|
        next [address, nil, "----"] unless pin

        address = pin[0]
        pin
      end
    end
  end

  module_function

  def files = Dir.glob(File.join(DIR, "*.json"))

  # The file's cases, or +sample+ of them picked by +random+.
  def cases(path, sample: nil, random: Random.new(1))
    tests = JSON.parse(File.read(path))
    sample ? tests.sample(sample, random:) : tests
  end

  def start(test)
    initial = test["initial"]
    bus = Bus.new(initial["ram"], test.fetch("ports", []))
    cpu = Badline::Z80.new(bus)
    bus.cpu = cpu
    REGISTERS.each { |name| cpu.public_send("#{name}=", initial[name]) }
    ALTERNATES.each { |name, attribute| cpu.public_send("#{attribute}=", initial[name]) }
    LATCHES.each { |name, attribute| cpu.public_send("#{attribute}=", initial[name] == 1) }
    [cpu, bus]
  end

  # Runs one case and returns what differs, empty if it passed.
  def run(test)
    cpu, bus = start(test)
    cpu.step!
    final = test["final"]
    errors = register_errors(cpu, final)
    errors << "cycles #{cpu.cycles} != #{test['cycles'].length}" if cpu.cycles != test["cycles"].length
    errors.concat(ram_errors(bus, final["ram"]))
    errors << "ports #{bus.ports} != #{test['ports']}" if bus.ports != test.fetch("ports", [])
    errors << pin_error(bus.pins(test["cycles"].length), test["cycles"]) if cpu.cycles == test["cycles"].length
    errors.compact
  end

  def register_errors(cpu, final)
    errors = REGISTERS.filter_map { |name| mismatch(name, cpu.public_send(name), final[name]) }
    errors += ALTERNATES.filter_map { |name, attribute| mismatch(name, cpu.public_send(attribute), final[name]) }
    errors + LATCHES.filter_map { |name, attribute| mismatch(name, cpu.public_send(attribute) ? 1 : 0, final[name]) }
  end

  def mismatch(name, actual, expected)
    "#{name} #{actual} != #{expected}" unless actual == expected
  end

  def ram_errors(bus, ram)
    ram.filter_map { |address, value| mismatch(format("ram[%04x]", address), bus.ram[address], value) }
  end

  def pin_error(actual, expected)
    index = actual.each_index.find { |i| actual[i] != expected[i] }
    "T#{index}: #{actual[index].inspect} != #{expected[index].inspect}" if index
  end
end
