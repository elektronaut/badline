# frozen_string_literal: true

module Badline
  class TimeOfDay
    include IntegerHelper

    CLOCK_HZ = 985_248 # PAL only for now.
    MAINS_HZ = 50      # The TOD pin is fed from the AC supply.

    def initialize(clock_hz: CLOCK_HZ, mains_hz: MAINS_HZ)
      # The accumulator advances mains_hz per cycle, so a TOD pin pulse has
      # arrived when it reaches clock_hz. Integer math keeps it exact.
      @cycles_per_pulse = clock_hz
      @mains_hz = mains_hz
      @accumulator = 0
      @pulses = 0
      @divider = 6
      @clock = { tenths: 0, seconds: 0, minutes: 0, hours: 12, pm: false }
      @alarm = { tenths: 0, seconds: 0, minutes: 0, hours: 0, pm: false }
      @latch = nil
      @stopped = false
    end

    # CRA bit 7 divides the TOD pin by 5 instead of 6. The divider has to
    # match the pin frequency to keep time, so PAL software selects 50 Hz.
    def fifty_hz=(enabled)
      @divider = enabled ? 5 : 6
    end

    def cycle!
      return if @stopped

      @accumulator += @mains_hz
      return if @accumulator < @cycles_per_pulse

      @accumulator -= @cycles_per_pulse
      @pulses += 1
      return if @pulses < @divider

      @pulses = 0
      advance
      yield if block_given? && alarm?
    end

    def tenths
      value = (@latch || @clock)[:tenths]
      @latch = nil
      bcd(value)
    end

    def seconds
      bcd((@latch || @clock)[:seconds])
    end

    def minutes
      bcd((@latch || @clock)[:minutes])
    end

    def hours
      @latch ||= @clock.dup
      bcd(@latch[:hours]) | (@latch[:pm] ? 0x80 : 0)
    end

    def write(field, value, alarm:)
      (alarm ? @alarm : @clock)[field] = bcd_to_i(value)
      # Start the clock again when writing tenths.
      resume if field == :tenths && !alarm
    end

    # 12-hour BCD value, bit 7 is the AM/PM flag.
    def write_hours(value, alarm:)
      target = alarm ? @alarm : @clock
      target[:hours] = bcd_to_i(value & 0x7f)
      target[:pm] = value.anybits?(0x80)
      # Halt the clock when writing hours, so that it doesn't
      # advance mid-update.
      @stopped = true unless alarm
    end

    private

    def resume
      @stopped = false
      @accumulator = 0
      @pulses = 0
    end

    def advance
      @clock[:tenths] += 1
      return if @clock[:tenths] < 10

      @clock[:tenths] = 0
      @clock[:seconds] += 1
      return if @clock[:seconds] < 60

      @clock[:seconds] = 0
      @clock[:minutes] += 1
      return if @clock[:minutes] < 60

      @clock[:minutes] = 0
      advance_hour
    end

    def advance_hour
      @clock[:hours] += 1
      @clock[:pm] = !@clock[:pm] if @clock[:hours] == 12
      @clock[:hours] = 1 if @clock[:hours] > 12
    end

    def alarm?
      %i[tenths seconds minutes hours pm].all? do |field|
        @clock[field] == @alarm[field]
      end
    end
  end
end
