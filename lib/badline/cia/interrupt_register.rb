# frozen_string_literal: true

module Badline
  class CIA
    # The interrupt control register: the source flags, their mask and the
    # IR bit that drives the interrupt line, with the 6526's acknowledge
    # timing.
    class InterruptRegister
      attr_reader :status, :mask

      def initialize
        @mask = Status.new([:timer_a, :timer_b, :alarm, :serial, :flag, 0, 0, 0])
        @status = Status.new([:timer_a, :timer_b, :alarm, :serial, :flag, 0, 0, :interrupt])
        @pending = 0
        @read = @read_last_cycle = @read_two_cycles_ago = nil
        @timer_b_bug = false
      end

      def cycle!
        @read_two_cycles_ago = @read_last_cycle
        @read_last_cycle = @read
        @read = nil
        return unless @pending.positive?

        @pending -= 1
        status.interrupt = true if @pending.zero?
      end

      def interrupted?
        status.value.anybits?(0x80)
      end

      # Schedules IR to rise after delay cycles, keeping an earlier one.
      def assert!(delay = 1)
        @pending = @pending.positive? ? [@pending, delay].min : delay
      end

      # Latch a source, pulling the interrupt line if it is armed.
      def flag(source)
        status.public_send(:"#{source}=", true)
        assert! if mask.public_send(:"#{source}?")
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
        value |= 0x80 if @read_last_cycle&.anybits?(0x80)
        status.value = 0x0
        @pending = 0
        value
      end

      # Bit 7 picks between setting and clearing the mask bits given.
      def write(value)
        if value.nobits?(0x80)
          mask.value &= ~(value & 0x1f)
        else
          mask.value |= (value & 0x1f)
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
    end
  end
end
