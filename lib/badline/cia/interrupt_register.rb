# frozen_string_literal: true

module Badline
  class CIA
    # The interrupt control register: the source flags, their mask and the
    # IR bit that drives the interrupt line, with the 6526's acknowledge
    # timing.
    class InterruptRegister
      attr_reader :status, :mask, :quiet

      # The 6526A is the faster of the two: see the rules below.
      def initialize(model = :mos6526)
        @fast = model == :mos6526a
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

      # Raises IR on this cycle.
      def assert_now
        status.interrupt = true
        @pending = 0
      end

      # Schedules IR to rise after delay cycles, keeping an earlier one.
      def assert!(delay = 1)
        @pending = @pending.positive? ? [@pending, delay].min : delay
        @quiet = false
      end

      # Latch a source, pulling the interrupt line if it is armed. The 6526
      # raises IR a cycle after the flag. The 6526A raises it on the flag's
      # own cycle, unless the ICR was read on the cycle before.
      def flag(source)
        bit = source_bit(source)
        @status.value |= bit
        return unless mask.value.anybits?(bit)

        @fast && @read_last_cycle.nil? ? assert_now : assert!
      end

      # The 6526 timer B bug: an underflow on the cycle after a read still
      # raises the flag, but the next read drops it unseen. The 6526A has
      # no such bug.
      def timer_b_underflow!
        @timer_b_bug = !@fast && !@read_last_cycle.nil?
        flag(:timer_b)
      end

      # A read releases the interrupt line at once, and cancels an assert
      # due on the next cycle, but its acknowledge lands a cycle late. On
      # the 6526 that holds only IR: the next cycle still reads IR set if it
      # was set, or about to be. The 6526A reads an IR about to rise as set
      # at once, and holds every bit it read: the next cycle reads them all
      # again, along with anything flagged since.
      def read
        status.timer_b = false if @timer_b_bug
        @timer_b_bug = false
        value = status.value
        value |= 0x80 if @fast && @pending == 1
        @read = @pending == 1 ? value | 0x80 : value
        @quiet = false
        value |= held(@read_last_cycle) if @read_last_cycle
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
          assert!(arm_delay) unless interrupted?
        elsif @pending == 1 && @read_two_cycles_ago
          # On the 6526, masking the pending source cancels the assert due
          # on the next cycle only while a read two cycles back is
          # acknowledging.
          @pending = 0
        end
      end

      private

      # Arming a pending source raises IR two cycles later on the 6526,
      # and one cycle later on the 6526A.
      def arm_delay = @fast ? 1 : 2

      # What a read on the cycle before still holds: IR on the 6526, and
      # every bit it read on the 6526A.
      def held(last) = @fast ? last : last & 0x80

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
