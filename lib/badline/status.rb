# frozen_string_literal: true

module Badline
  # A register of flag bits. +flags+ names each bit from bit 0 up: a
  # symbol for a flag, or 0 or 1 for a bit that always reads as that. The
  # subclasses below carry the accessors for each register layout.
  class Status
    attr_reader :value, :flags, :bitmask, :low_mask, :high_mask

    def initialize(flags = [], value: 0x0)
      @flags = flags

      @bitmask = create_mask { |f| f.is_a?(Symbol) }
      @low_mask = create_mask { |f| f.is_a?(Integer) && f.zero? }
      @high_mask = create_mask { |f| f.is_a?(Integer) && f == 1 }

      self.value = value
    end

    def value=(new_value)
      @value = (new_value | high_mask) & ~low_mask
    end

    private

    def create_mask(&predicate)
      flags.each.with_index.inject(0) do |mask, (flag, i)|
        mask + (predicate.call(flag) ? 1 << i : 0)
      end
    end
  end

  # The 6510 processor status register.
  class CPUStatus < Status
    def carry=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x01 : @value & ~0x01
    end

    def carry? = @value & 0x01 != 0

    def carry = @value.nobits?(0x01) ? 0 : 1

    def zero=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x02 : @value & ~0x02
    end

    def zero? = @value & 0x02 != 0

    def zero = @value.nobits?(0x02) ? 0 : 1

    def interrupt=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x04 : @value & ~0x04
    end

    def interrupt? = @value & 0x04 != 0

    def interrupt = @value.nobits?(0x04) ? 0 : 1

    def decimal=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x08 : @value & ~0x08
    end

    def decimal? = @value & 0x08 != 0

    def decimal = @value.nobits?(0x08) ? 0 : 1

    def break=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x10 : @value & ~0x10
    end

    def break? = @value & 0x10 != 0

    def break = @value.nobits?(0x10) ? 0 : 1

    def overflow=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x40 : @value & ~0x40
    end

    def overflow? = @value & 0x40 != 0

    def overflow = @value.nobits?(0x40) ? 0 : 1

    def negative=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x80 : @value & ~0x80
    end

    def negative? = @value & 0x80 != 0

    def negative = @value.nobits?(0x80) ? 0 : 1
  end

  # The 6510 I/O port at $01.
  class PortStatus < Status
    def basic=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x01 : @value & ~0x01
    end

    def basic? = @value & 0x01 != 0

    def basic = @value.nobits?(0x01) ? 0 : 1

    def kernal=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x02 : @value & ~0x02
    end

    def kernal? = @value & 0x02 != 0

    def kernal = @value.nobits?(0x02) ? 0 : 1

    def io=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x04 : @value & ~0x04
    end

    def io? = @value & 0x04 != 0

    def io = @value.nobits?(0x04) ? 0 : 1

    def tape_out=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x08 : @value & ~0x08
    end

    def tape_out? = @value & 0x08 != 0

    def tape_out = @value.nobits?(0x08) ? 0 : 1

    def tape_switch=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x10 : @value & ~0x10
    end

    def tape_switch? = @value & 0x10 != 0

    def tape_switch = @value.nobits?(0x10) ? 0 : 1

    def tape_motor=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x20 : @value & ~0x20
    end

    def tape_motor? = @value & 0x20 != 0

    def tape_motor = @value.nobits?(0x20) ? 0 : 1
  end

  # A CIA timer control register, CRA or CRB. Bits 5-7 differ between the two.
  class ControlRegister < Status
    def start=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x01 : @value & ~0x01
    end

    def start? = @value & 0x01 != 0

    def start = @value.nobits?(0x01) ? 0 : 1

    def output=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x02 : @value & ~0x02
    end

    def output? = @value & 0x02 != 0

    def output = @value.nobits?(0x02) ? 0 : 1

    def out_mode=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x04 : @value & ~0x04
    end

    def out_mode? = @value & 0x04 != 0

    def out_mode = @value.nobits?(0x04) ? 0 : 1

    def run_mode=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x08 : @value & ~0x08
    end

    def run_mode? = @value & 0x08 != 0

    def run_mode = @value.nobits?(0x08) ? 0 : 1

    def load=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x10 : @value & ~0x10
    end

    def load? = @value & 0x10 != 0

    def load = @value.nobits?(0x10) ? 0 : 1

    def in_mode=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x20 : @value & ~0x20
    end

    def in_mode? = @value & 0x20 != 0

    def in_mode = @value.nobits?(0x20) ? 0 : 1

    def serial_mode=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x40 : @value & ~0x40
    end

    def serial_mode? = @value & 0x40 != 0

    def serial_mode = @value.nobits?(0x40) ? 0 : 1

    def clock_frequency=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x80 : @value & ~0x80
    end

    def clock_frequency? = @value & 0x80 != 0

    def clock_frequency = @value.nobits?(0x80) ? 0 : 1

    def in_cnt=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x20 : @value & ~0x20
    end

    def in_cnt? = @value & 0x20 != 0

    def in_cnt = @value.nobits?(0x20) ? 0 : 1

    def in_timer_a=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x40 : @value & ~0x40
    end

    def in_timer_a? = @value & 0x40 != 0

    def in_timer_a = @value.nobits?(0x40) ? 0 : 1

    def alarm=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x80 : @value & ~0x80
    end

    def alarm? = @value & 0x80 != 0

    def alarm = @value.nobits?(0x80) ? 0 : 1
  end

  # The CIA interrupt sources, as flags or as their mask.
  class InterruptFlags < Status
    def timer_a=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x01 : @value & ~0x01
    end

    def timer_a? = @value & 0x01 != 0

    def timer_a = @value.nobits?(0x01) ? 0 : 1

    def timer_b=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x02 : @value & ~0x02
    end

    def timer_b? = @value & 0x02 != 0

    def timer_b = @value.nobits?(0x02) ? 0 : 1

    def alarm=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x04 : @value & ~0x04
    end

    def alarm? = @value & 0x04 != 0

    def alarm = @value.nobits?(0x04) ? 0 : 1

    def serial=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x08 : @value & ~0x08
    end

    def serial? = @value & 0x08 != 0

    def serial = @value.nobits?(0x08) ? 0 : 1

    def flag=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x10 : @value & ~0x10
    end

    def flag? = @value & 0x10 != 0

    def flag = @value.nobits?(0x10) ? 0 : 1

    def interrupt=(enabled)
      @value = enabled && enabled != 0 ? @value | 0x80 : @value & ~0x80
    end

    def interrupt? = @value & 0x80 != 0

    def interrupt = @value.nobits?(0x80) ? 0 : 1
  end
end
