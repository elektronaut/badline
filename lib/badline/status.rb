# frozen_string_literal: true

module Badline
  class Status
    attr_reader :value, :flags, :bitmask, :low_mask, :high_mask

    def initialize(flags = [], value: 0x0)
      @flags = flags

      @bitmask = create_mask { |f| f.is_a?(Symbol) }
      @low_mask = create_mask { |f| f.is_a?(Integer) && f.zero? }
      @high_mask = create_mask { |f| f.is_a?(Integer) && f == 1 }

      self.value = value

      define_accessors!
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

    def define_accessors!
      flags.each_with_index do |name, i|
        next unless name.is_a?(Symbol)

        mask = 1 << i
        define_singleton_method("#{name}=") do |enabled|
          update(mask, enabled)
        end
        define_singleton_method("#{name}?") do
          !@value.nobits?(mask)
        end
        define_singleton_method(name) do
          @value.nobits?(mask) ? 0 : 1
        end
      end
    end

    def update(mask, enabled)
      @value = enabled && enabled != 0 ? @value | mask : @value & ~mask
    end
  end
end
