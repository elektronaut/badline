# frozen_string_literal: true

module Badline
  class CIA
    # The interrupt control register: the source flags, their mask and the
    # IR bit that drives the interrupt line, with the 6526's acknowledge
    # timing.
    class InterruptRegister
      attr_reader :status, :mask, :quiet

      def initialize
        @mask = InterruptFlags.new([:timer_a, :timer_b, :alarm, :serial, :flag, 0, 0, 0])
        @status = InterruptFlags.new([:timer_a, :timer_b, :alarm, :serial, :flag, 0, 0, :interrupt])
        @pending = 0
        @read = @read_last_cycle = @read_two_cycles_ago = nil
        @timer_b_bug = false
        @quiet = true
      end

      # The CIA skips this while quiet: no read is recent enough to matter
      # and no assert is due.
      def cycle!
        @read_two_cycles_ago = @read_last_cycle
        @read_last_cycle = @read
        @read = nil
        if @pending.positive?
          @pending -= 1
          status.interrupt = true if @pending.zero?
        end
        @quiet = @pending.zero? && @read_last_cycle.nil? && @read_two_cycles_ago.nil?
      end

      def interrupted? = status.value >= 0x80

      # Schedules IR to rise after delay cycles, keeping an earlier one.
      def assert!(delay = 1)
        @pending = @pending.positive? ? [@pending, delay].min : delay
        @quiet = false
      end

      # Latch a source, pulling the interrupt line if it is armed.
      def flag(source)
        bit = source_bit(source)
        @status.value |= bit
        assert! if mask.value.anybits?(bit)
      end

      # The 6526 timer B bug: an underflow on the cycle after a read still
      # raises the flag, but the next read drops it unseen.
      def timer_b_underflow!
        @timer_b_bug = !@read_last_cycle.nil?
        flag(:timer_b)
      end

      # A read releases the interrupt line at once, and cancels an assert
      # due on the next cycle, but on the 6526 its IR acknowledge lands a
      # cycle late: the next cycle still reads IR set if it was set, or
      # about to be.
      def read
        status.timer_b = false if @timer_b_bug
        @timer_b_bug = false
        value = status.value
        @read = @pending == 1 ? value | 0x80 : value
        @quiet = false
        value |= 0x80 if @read_last_cycle&.anybits?(0x80)
        status.value = 0x0
        @pending = 0
        value
      end

      # Bit 7 picks between setting and clearing the mask bits given.
      def write(value)
        if value.nobits?(0x80)
          @mask.value &= ~(value & 0x1f)
        else
          @mask.value |= (value & 0x1f)
        end
        if mask.value.anybits?(status.value & 0x1f)
          assert!(2) unless interrupted?
        elsif @pending == 1 && @read_two_cycles_ago
          # On the 6526, masking the pending source cancels the assert due
          # on the next cycle only while a read two cycles back is
          # acknowledging.
          @pending = 0
        end
      end

      private

      def source_bit(source)
        case source
        when :timer_a then 0x01
        when :timer_b then 0x02
        when :alarm then 0x04
        when :serial then 0x08
        when :flag then 0x10
        else raise ArgumentError, "unknown interrupt source #{source}"
        end
      end
    end
  end
end
