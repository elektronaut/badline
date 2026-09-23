# frozen_string_literal: true

module Badline
  class Status
    attr_reader :value, :flags, :bitmask, :low_mask, :high_mask

    class << self
      # Each flag layout gets a subclass of its own, with the flag accessors
      # compiled as ordinary methods rather than closures.
      def new(flags = [], value: 0x0)
        return super unless equal?(Status)

        layout(flags).new(flags, value:)
      end

      private

      def layout(flags)
        @layouts ||= {}
        @layouts[flags] ||= Class.new(Status) { define_accessors(flags) }
      end

      def define_accessors(flags)
        flags.each_with_index do |name, i|
          next unless name.is_a?(Symbol)

          mask = 1 << i
          class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
            def #{name}=(enabled)                                                   # def carry=(enabled)
              @value = enabled && enabled != 0 ? @value | #{mask} : @value & #{~mask} #   @value = ... | 0x01 : ... & ~0x01
            end                                                                     # end
            def #{name}? = @value & #{mask} != 0                                    # def carry? = @value & 0x01 != 0
            def #{name} = @value & #{mask} == 0 ? 0 : 1                             # def carry = ... ? 0 : 1
          RUBY
        end
      end
    end

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
end
