# frozen_string_literal: true

module Badline
  # A byte of named bit flags. The vocabulary is given per instance; the
  # accessors below cover every flag name the machine uses.
  #
  # They are written out rather than installed with
  # define_singleton_method: a method defined at runtime has no name an
  # AOT compiler can resolve, and a plain method beats a singleton class
  # per instance anyway.
  class Status
    attr_reader :value, :flags, :bitmask, :low_mask, :high_mask

    def initialize(flags = [], value: 0x0)
      @flags = flags
      @masks = {}
      flags.each_with_index { |flag, i| @masks[flag] = 1 << i if flag.is_a?(Symbol) }

      @bitmask = create_mask { |f| f.is_a?(Symbol) }
      @low_mask = create_mask { |f| f.is_a?(Integer) && f.zero? }
      @high_mask = create_mask { |f| f.is_a?(Integer) && f == 1 }

      self.value = value
    end

    def value=(new_value)
      @value = (new_value | high_mask) & ~low_mask
    end

    # Access by name, for a flag with no accessor of its own.
    def set?(name) = !@value.nobits?(mask_of(name))

    def bit(name) = @value.nobits?(mask_of(name)) ? 0 : 1

    def set(name, enabled)
      update(mask_of(name), enabled)
    end

    # CPU status register

    def carry? = set?(:carry)

    def carry = bit(:carry)

    def carry=(enabled)
      set(:carry, enabled)
    end

    def zero? = set?(:zero)

    def zero = bit(:zero)

    def zero=(enabled)
      set(:zero, enabled)
    end

    def interrupt? = set?(:interrupt)

    def interrupt = bit(:interrupt)

    def interrupt=(enabled)
      set(:interrupt, enabled)
    end

    def decimal? = set?(:decimal)

    def decimal = bit(:decimal)

    def decimal=(enabled)
      set(:decimal, enabled)
    end

    def break? = set?(:break)

    def break = bit(:break)

    def break=(enabled)
      set(:break, enabled)
    end

    def overflow? = set?(:overflow)

    def overflow = bit(:overflow)

    def overflow=(enabled)
      set(:overflow, enabled)
    end

    def negative? = set?(:negative)

    def negative = bit(:negative)

    def negative=(enabled)
      set(:negative, enabled)
    end

    # Processor port ($01)

    def basic? = set?(:basic)

    def basic = bit(:basic)

    def basic=(enabled)
      set(:basic, enabled)
    end

    def kernal? = set?(:kernal)

    def kernal = bit(:kernal)

    def kernal=(enabled)
      set(:kernal, enabled)
    end

    def io? = set?(:io)

    def io = bit(:io)

    def io=(enabled)
      set(:io, enabled)
    end

    def tape_out? = set?(:tape_out)

    def tape_out = bit(:tape_out)

    def tape_out=(enabled)
      set(:tape_out, enabled)
    end

    def tape_switch? = set?(:tape_switch)

    def tape_switch = bit(:tape_switch)

    def tape_switch=(enabled)
      set(:tape_switch, enabled)
    end

    def tape_motor? = set?(:tape_motor)

    def tape_motor = bit(:tape_motor)

    def tape_motor=(enabled)
      set(:tape_motor, enabled)
    end

    # CIA interrupt control/status

    def timer_a? = set?(:timer_a)

    def timer_a = bit(:timer_a)

    def timer_a=(enabled)
      set(:timer_a, enabled)
    end

    def timer_b? = set?(:timer_b)

    def timer_b = bit(:timer_b)

    def timer_b=(enabled)
      set(:timer_b, enabled)
    end

    def alarm? = set?(:alarm)

    def alarm = bit(:alarm)

    def alarm=(enabled)
      set(:alarm, enabled)
    end

    def serial? = set?(:serial)

    def serial = bit(:serial)

    def serial=(enabled)
      set(:serial, enabled)
    end

    def flag? = set?(:flag)

    def flag = bit(:flag)

    def flag=(enabled)
      set(:flag, enabled)
    end

    # CIA control registers A/B

    def start? = set?(:start)

    def start = bit(:start)

    def start=(enabled)
      set(:start, enabled)
    end

    def output? = set?(:output)

    def output = bit(:output)

    def output=(enabled)
      set(:output, enabled)
    end

    def out_mode? = set?(:out_mode)

    def out_mode = bit(:out_mode)

    def out_mode=(enabled)
      set(:out_mode, enabled)
    end

    def run_mode? = set?(:run_mode)

    def run_mode = bit(:run_mode)

    def run_mode=(enabled)
      set(:run_mode, enabled)
    end

    def load? = set?(:load)

    def load = bit(:load)

    def load=(enabled)
      set(:load, enabled)
    end

    def in_mode? = set?(:in_mode)

    def in_mode = bit(:in_mode)

    def in_mode=(enabled)
      set(:in_mode, enabled)
    end

    def serial_mode? = set?(:serial_mode)

    def serial_mode = bit(:serial_mode)

    def serial_mode=(enabled)
      set(:serial_mode, enabled)
    end

    def clock_frequency? = set?(:clock_frequency)

    def clock_frequency = bit(:clock_frequency)

    def clock_frequency=(enabled)
      set(:clock_frequency, enabled)
    end

    def in_cnt? = set?(:in_cnt)

    def in_cnt = bit(:in_cnt)

    def in_cnt=(enabled)
      set(:in_cnt, enabled)
    end

    def in_timer_a? = set?(:in_timer_a)

    def in_timer_a = bit(:in_timer_a)

    def in_timer_a=(enabled)
      set(:in_timer_a, enabled)
    end

    private

    def mask_of(name)
      mask = @masks[name]
      raise NoMethodError, "undefined flag #{name} for #{self.class}" if mask.nil?

      mask
    end

    def create_mask(&predicate)
      flags.each.with_index.inject(0) do |mask, (flag, i)|
        mask + (predicate.call(flag) ? 1 << i : 0)
      end
    end

    def update(mask, enabled)
      self.value = if enabled && enabled != 0
                     value | mask
                   else
                     value & ~mask
                   end
    end
  end
end
