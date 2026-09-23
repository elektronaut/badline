# frozen_string_literal: true

module Badline
  class TimeOfDay
    CLOCK_HZ = 985_248 # PAL only for now.
    MAINS_HZ = 50      # The TOD pin is fed from the AC supply.

    def initialize(clock_hz: CLOCK_HZ, mains_hz: MAINS_HZ)
      # The accumulator advances mains_hz per cycle, so a TOD pin pulse has
      # arrived when it reaches clock_hz. Integer math keeps it exact.
      @cycles_per_pulse = clock_hz
      @mains_hz = mains_hz
      @accumulator = 0
      @pulses = 0
      @clock = { tenths: 0x00, seconds: 0x00, minutes: 0x00, hours: 0x01 }
      @alarm = { tenths: 0x00, seconds: 0x00, minutes: 0x00, hours: 0x00 }
      @latch = nil
      @stopped = true
      @alarm_pending = false
      self.fifty_hz = false
    end

    # CRA bit 7 divides the TOD pin by 5 instead of 6. The divider has to
    # match the pin frequency to keep time, so PAL software selects 50 Hz.
    def fifty_hz=(enabled)
      @match = enabled ? 4 : 5
    end

    def cycle!
      @accumulator += @mains_hz
      pulse! if @accumulator >= @cycles_per_pulse
      return unless @alarm_pending

      @alarm_pending = false
      yield if block_given?
    end

    def tenths
      value = (@latch || @clock)[:tenths]
      @latch = nil
      value
    end

    def seconds = (@latch || @clock)[:seconds]
    def minutes = (@latch || @clock)[:minutes]

    def hours
      @latch ||= @clock.dup
      @latch[:hours]
    end

    # The clock and alarm as stored, read without latching the clock.
    def registers
      [@clock[:tenths], @clock[:seconds], @clock[:minutes], @clock[:hours],
       @alarm[:tenths], @alarm[:seconds], @alarm[:minutes], @alarm[:hours],
       @stopped ? 1 : 0, @latch ? 1 : 0]
    end

    def write(field, value, alarm:)
      # The frequency counter is held clear while the clock is stopped, and
      # starts counting again from the write to tenths that restarts it.
      if field == :tenths && !alarm && @stopped
        @pulses = 0
        @stopped = false
      end
      store(field, value & (field == :tenths ? 0x0f : 0x7f), alarm: alarm)
    end

    # 12-hour BCD value, bit 7 is the AM/PM flag.
    def write_hours(value, alarm:)
      value &= 0x9f
      # Writing 12 to the hour register flips the AM/PM bit, the same way a
      # carry into 12 does. Writing the alarm hours does not.
      value ^= 0x80 if !alarm && (value & 0x1f) == 0x12
      # Halt the clock when writing hours, so that it doesn't
      # advance mid-update.
      @stopped = true unless alarm
      store(:hours, value, alarm: alarm)
    end

    private

    def store(field, value, alarm:)
      target = alarm ? @alarm : @clock
      return if target[field] == value

      target[field] = value
      @alarm_pending = true if alarm?
    end

    def pulse!
      @accumulator -= @cycles_per_pulse
      return if @stopped

      # A three-bit ring counter with six states, compared against the
      # divider on each pin pulse rather than on its way past it.
      if @pulses == @match
        @pulses = 0
        advance
      else
        @pulses += 1
        @pulses = 0 if @pulses > 5
      end
    end

    def advance
      tenths = (@clock[:tenths] + 1) & 0x0f
      @clock[:tenths] = tenths == 10 ? 0 : tenths
      carry_seconds if tenths == 10
      @alarm_pending = true if alarm?
    end

    def carry_seconds
      return unless advance_pair(:seconds)
      return unless advance_pair(:minutes)

      advance_hours
    end

    # Seconds and minutes hold a four-bit low digit that carries at ten into
    # a three-bit high digit that carries out at six. Both are plain binary
    # counters, so out-of-range BCD counts up from where it was written.
    def advance_pair(field)
      low = ((@clock[field] & 0x0f) + 1) & 0x0f
      high = (@clock[field] >> 4) & 0x07
      carry = false

      if low == 10
        low = 0
        high = (high + 1) & 0x07
        if high == 6
          high = 0
          carry = true
        end
      end

      @clock[field] = (high << 4) | low
      carry
    end

    # The hour runs 9 -> 10 and 12 -> 1 by swapping its two digits, and the
    # AM/PM bit flips as it passes through 12.
    def advance_hours
      pm = @clock[:hours] & 0x80
      high = (@clock[:hours] >> 4) & 0x01
      low = @clock[:hours] & 0x0f

      if (high == 1 && low == 2) || (high.zero? && low == 9)
        low = high
        high ^= 1
      else
        low = (low + 1) & 0x0f
        pm ^= 0x80 if high == 1 && low == 2
      end

      @clock[:hours] = pm | (high << 4) | low
    end

    def alarm? = @clock == @alarm
  end
end
