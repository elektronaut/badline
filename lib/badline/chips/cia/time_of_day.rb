# frozen_string_literal: true

module Badline
  class TimeOfDay
    # The TOD pin is fed from the AC supply. A CIA passes its region's
    # clock and mains frequency, and these are PAL's.
    CLOCK_HZ = Region::PAL.clock_hz
    MAINS_HZ = Region::PAL.mains_hz

    FIELDS = %i[tenths seconds minutes hours].freeze

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

    # The clock and the alarm, field by field in FIELDS order, the latch,
    # and the divider's phase.
    def save_state(out)
      out.int(@accumulator).int(@pulses).int(@match).boolean(@stopped).boolean(@alarm_pending)
      FIELDS.each { |field| out.int(@clock[field]).int(@alarm[field]) }
      out.boolean(!@latch.nil?)
      FIELDS.each { |field| out.int(@latch[field]) } if @latch
    end

    def load_state(input)
      @accumulator = input.int
      @pulses = input.int
      @match = input.int
      @stopped = input.boolean?
      @alarm_pending = input.boolean?
      FIELDS.each do |field|
        @clock[field] = input.int
        @alarm[field] = input.int
      end
      @latch = input.boolean? ? FIELDS.to_h { |field| [field, input.int] } : nil
    end

    # Whether the clock is stopped, or gets no pulses on its pin, with no
    # alarm to raise, so its cycles move only the divider's phase.
    def quiet? = (@stopped || @mains_hz.zero?) && !@alarm_pending

    # Runs +cycles+ quiet cycles at once.
    def fast_forward(cycles)
      @accumulator = (@accumulator + (cycles * @mains_hz)) % @cycles_per_pulse
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

    attr_reader :pulses

    # The clock as a read of the tenths would see it: the latch while the
    # clock is latched. In FIELDS order.
    def latched_fields = FIELDS.map { |field| (@latch || @clock)[field] }

    # The cycles until the clock next steps a tenth, as VICE counts them.
    def cycles_to_tenth
      to_pulse = (@cycles_per_pulse - @accumulator + @mains_hz - 1) / @mains_hz
      to_pulse + ([@match - @pulses, 0].max * @cycles_per_pulse / @mains_hz)
    end

    # Sets the clock, the alarm and the latch from VICE's fields, in FIELDS
    # order, the latch nil while unlatched.
    def restore_fields(clock, alarm, latch)
      FIELDS.each_with_index do |field, i|
        @clock[field] = clock[i]
        @alarm[field] = alarm[i]
      end
      @latch = latch && FIELDS.each_with_index.to_h { |field, i| [field, latch[i]] }
    end

    # Sets whether the clock is stopped, the pulses counted towards the
    # next tenth and the cycles until it, placing the divider so the tenth
    # lands then.
    def restore_divider(stopped, pulses, cycles_to_tenth)
      @stopped = stopped
      @pulses = pulses
      to_pulse = cycles_to_tenth - ([@match - pulses, 0].max * @cycles_per_pulse / @mains_hz)
      @accumulator = (@cycles_per_pulse - (to_pulse * @mains_hz)).clamp(0, @cycles_per_pulse - 1)
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
