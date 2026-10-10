# frozen_string_literal: true

module Badline
  # A digest of the machine's state at one cycle, for comparing two runs of
  # the same scenario, on two builds or two revisions. Each component is
  # hashed on its own with 32-bit FNV-1a, so a mismatch names the part of the
  # machine that went its own way. Nothing is read through a chip's bus
  # interface, so taking a checkpoint leaves the machine as it was.
  #
  # Checkpoint.take digests a C64's components, COMPONENTS.
  # Vic20Checkpoint and C128Checkpoint digest the other families', each
  # with a list of its own, which a checkpoint carries as +components+.
  #
  # Colour RAM is digested as the four bits each cell stores: the upper
  # nibble a CPU read sees comes off the open bus.
  class Checkpoint
    COMPONENTS = %w[cpu ram color_ram display vic cia1 cia2 sid].freeze

    FNV_OFFSET = 0x811c9dc5
    FNV_PRIME = 0x01000193

    attr_reader :cycle, :digests, :components

    class << self
      def take(computer)
        new(computer.cycles, [
              fnv1a(cpu_state(computer.cpu)),
              fnv1a(ram(computer.ram, 0x10000)),
              fnv1a(color_ram(computer.address_bus.color_ram, 0xd800)),
              fnv1a(computer.vic.display),
              fnv1a(vic_state(computer.vic)),
              fnv1a(cia_state(computer.cia1)),
              fnv1a(cia_state(computer.cia2)),
              fnv1a(Array.new(0x20) { |reg| computer.sid.register(reg) })
            ])
      end

      # Reads a line written by #to_s, with a digest for each of
      # `components`.
      def parse(line, components = COMPONENTS)
        fields = line.split
        digests = components.map do |name|
          field = fields.find { |f| f.start_with?("#{name}=") }
          raise ArgumentError, "no #{name} digest in #{line.inspect}" unless field

          field.split("=").last.to_i(16)
        end
        new(fields.first.to_i, digests, components)
      end

      def fnv1a(values)
        hash = FNV_OFFSET
        values.each { |value| hash = ((hash ^ (value & 0xffffffff)) * FNV_PRIME) & 0xffffffff }
        hash
      end

      # The registers and cycle count of a 6502 or an 8502.
      def cpu_state(cpu)
        [cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p, cpu.cycles]
      end

      # The first `length` bytes of `memory`.
      def ram(memory, length)
        Array.new(length) { |addr| memory.peek(addr) }
      end

      # The 1K of colour RAM at `start`.
      def color_ram(memory, start)
        Array.new(0x400) { |offset| memory.nibble(start + offset) }
      end

      # A VIC-II's or a VIC-I's registers and beam position.
      def vic_state(vic)
        vic.register_file + [vic.rasterline, vic.column]
      end

      def cia_state(cia)
        start = cia.start
        [cia.peek(start), cia.peek(start + 1), cia.peek(start + 2), cia.peek(start + 3),
         cia.timer_a, cia.timer_a_latch, cia.timer_b, cia.timer_b_latch, cia.serial.data,
         cia.control_a.value, cia.control_b.value, cia.interrupt_status.value,
         cia.interrupt_control.value] + cia.time_of_day.registers
      end
    end

    def initialize(cycle, digests, components = COMPONENTS)
      @cycle = cycle
      @digests = digests
      @components = components
    end

    # The components whose digests differ from `other`'s.
    def differences(other)
      components.each_index.reject { |i| digests[i] == other.digests[i] }.map { |i| components[i] }
    end

    def ==(other)
      other.is_a?(Checkpoint) && cycle == other.cycle && components == other.components && digests == other.digests
    end

    def to_s
      fields = components.each_index.map { |i| "#{components[i]}=#{digests[i].to_s(16).rjust(8, '0')}" }
      "#{cycle} #{fields.join(' ')}"
    end
  end
end
