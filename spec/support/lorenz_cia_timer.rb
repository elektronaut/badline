# frozen_string_literal: true

# The expected results of Wolfgang Lorenz's cia1ta and cia1tb, transcribed
# from the xNNN routines in
# vendor/VICE-testprogs/general/Lorenz-2.15/src/cia1ta.s, old-CIA build
# (NEWCIA = 0, the build the suite image runs).
#
# Each cell writes the timer's latch low and control ("init", the source's
# i4 and ie), then a new latch low and control ("before", b4 and be), and
# reads back the counter low, the ICR and the control register. cia1tb is
# the same test on timer B, which reports through ICR bit 1, not bit 0.
module LorenzCiaTimer
  INIT_CONTROLS = [0x10, 0x11, 0x18, 0x19].freeze
  BEFORE_CONTROLS = [0x00, 0x01, 0x08, 0x09, 0x10, 0x11, 0x18, 0x19].freeze

  module_function

  # Every cell the test walks: init from 30 down to 0, before from 20 down
  # to 0, and the 32 control combinations. [init, init_control, before,
  # before_control]
  def cells
    30.downto(0).flat_map do |init|
      20.downto(0).flat_map do |before|
        INIT_CONTROLS.product(BEFORE_CONTROLS).map do |init_control, before_control|
          [init, init_control, before, before_control]
        end
      end
    end
  end

  # [counter low, ICR, control] for timer :a or :b
  def expected(timer, init, init_control, before, before_control)
    routines = init_control.anybits?(0x01) ? RunningInit : StoppedInit
    label = format("x%<init>x%<before>02x", init: init_control & 0x0f, before: before_control)
    counter, icr, control = routines.public_send(label, init, before, before_control)
    icr = (icr & 0x80) | ((icr & 0x01) << 1) if timer == :b
    [counter, icr, control]
  end

  # The ICR a count running into the new latch leaves: bit 0 below one
  # bound, bit 7 below another
  def running_icr(flag, irq) = (flag ? 0x01 : 0) | (irq ? 0x80 : 0)

  # before less the correction, unless that would reach zero or below
  def subtracted(before, correction) = before > correction ? before - correction : before

  # The routines for init controls $10 and $18: the timer is stopped when
  # the cell starts.
  module StoppedInit
    module_function

    def plain(init, _before, before_control) = [init, 0x00, before_control]

    def x001(init, before, _before_control)
      counter = if init >= 3 then init - 2
                elsif init.zero? && before >= 2 then before - 1
                else before
                end
      [counter, LorenzCiaTimer.running_icr(init < 7, init < 6), 0x01]
    end

    def x009(init, before, _before_control)
      [init >= 3 ? init - 2 : before, LorenzCiaTimer.running_icr(init < 7, init < 6), init >= 0x0b ? 0x09 : 0x08]
    end

    def reloaded(_init, before, before_control) = [before, 0x00, before_control & 0x09]

    def x011(init, before, before_control)
      icr = LorenzCiaTimer.running_icr(before < 6, before < 5)
      icr |= 0x81 if init.zero?
      [before >= 2 ? before - 1 : before, icr, before_control & 0x09]
    end

    def x019(init, before, _before_control)
      icr = LorenzCiaTimer.running_icr(before < 6, before < 5)
      icr |= 0x81 if init.zero?
      counter = before >= 2 && !init.zero? ? before - 1 : before
      [counter, icr, init.zero? || before < 0x0a ? 0x08 : 0x09]
    end

    {
      plain: %i[x000 x008 x800 x808], reloaded: %i[x010 x018 x810 x818],
      x001: %i[x801], x009: %i[x809], x011: %i[x811], x019: %i[x819]
    }.each do |routine, labels|
      labels.each { |label| singleton_class.alias_method(label, routine) }
    end
  end

  # The routines for init controls $11 and $19: the timer is running when
  # the cell starts.
  module RunningInit
    X100_SUB = [5, 5, 5, 3, 1, 5, 4, 3, 2, 1].freeze
    X100_SPECIAL = [0x71, 0x62, 0x53, 0x52, 0x51, 0x31, 0x23, 0x22, 0x21, 0x13,
                    0x12, 0x11, 0x03, 0x02, 0x01, 0x00].freeze
    X100_CORR = [0, 1, 2, 0, 0, 0, 2, 0, 0, 2, 0, 0, 2, 0, 0, 0].freeze

    X101_SUB = [7, 7, 7, 5, 3, 7, 6, 5, 4, 3, 2, 1].freeze
    X101_SPECIAL = [0x82, 0x73, 0x64, 0x63, 0x55, 0x54, 0x52, 0x33, 0x25, 0x24,
                    0x22, 0x15, 0x14, 0x12, 0x05, 0x04, 0x02].freeze
    X101_CORR = [1, 2, 3, 1, 4, 2, 1, 2, 4, 2, 1, 4, 2, 1, 4, 2, 1].freeze

    X109_SUB = [7, 7, 7, 5, 3, 7, 6, 5, 4, 3, 0, 0].freeze
    X109_B4COMP = [0x10, 0x10, 0x10, 0x0e, 0x0c, 0x10, 0x0f, 0x0e, 0x0d, 0x0c].freeze

    X119_NODEC = [0x82, 0x73, 0x72, 0x64, 0x63, 0x55, 0x54, 0x52, 0x33, 0x32,
                  0x25, 0x24, 0x22, 0x15, 0x14, 0x12, 0x05, 0x04, 0x02].freeze

    X901_SUB = [1, 0, 0, 0, 0, 2, 2, 2, 2, 2, 0, 1, 0, 0].freeze
    X909_SUB = [0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 0, 0, 0, 0].freeze

    module_function

    def x100(init, before, before_control)
      return [init - 0x0b, 0x00, before_control] if init >= 0x0b
      return [before, 0x81, before_control] if init >= 0x0a
      return [before - X100_SUB[init], 0x81, before_control] if before >= X100_SUB[init]

      [special(X100_SPECIAL, X100_CORR, (init << 4) | before) || before, 0x81, before_control]
    end

    def x101(init, before, _before_control)
      return [*past_reload(init), 0x01] if init > 0x0d
      return [before, 0x81, 0x01] if init >= 0x0c
      return [before - X101_SUB[init], 0x81, 0x01] if before > X101_SUB[init]

      [special(X101_SPECIAL, X101_CORR, (init << 4) | before) || before, 0x81, 0x01]
    end

    def x109(init, before, _before_control)
      counter, icr = if init > 0x0d then past_reload(init)
                     elsif init >= 0x0c then [before, 0x81]
                     else [LorenzCiaTimer.subtracted(before, X109_SUB[init]), 0x81]
                     end
      started = init >= 0x16 || (init < 0x0a && before >= X109_B4COMP[init])
      [counter, icr, started ? 0x09 : 0x08]
    end

    # x101 and x109 once the count has run past the reload
    def past_reload(init)
      counter = init - 0x0d
      [counter, { 4 => 0x01 }.fetch(counter) { counter < 4 ? 0x81 : 0x00 }]
    end

    def x110(init, before, before_control) = [before, init < 0x0b ? 0x81 : 0x00, before_control & 0x09]

    def x111(init, before, before_control)
      icr = LorenzCiaTimer.running_icr(before < 6, before < 5)
      icr |= 0x81 if init.zero?
      icr = 0x81 if init < 0x0c
      [before >= 2 ? before - 1 : before, icr, before_control & 0x09]
    end

    def x119(init, before, _before_control)
      icr = LorenzCiaTimer.running_icr(before < 6, before < 5)
      icr |= 0x81 if init < 0x0c
      stop = (0x0a...0x0c).cover?(init) || before < 0x0a
      [x119_counter(init, before), icr, stop ? 0x08 : 0x09]
    end

    def x119_counter(init, before)
      return before if before < 2 || (0x0a...0x0c).cover?(init)
      return before - 1 if init >= 0x0c || before >= 0x0f

      X119_NODEC.include?((init << 4) | before) ? before : before - 1
    end

    def x900(init, before, before_control)
      return [init, 0x81, before_control] if init < 5
      return [init - 0x0b, 0x00, before_control] if init >= 0x0b

      [before, 0x81, before_control]
    end

    def x901(init, before, _before_control)
      counter = if init >= 0x0e then init - 0x0d
                elsif [3, 4].include?(init) then init - 2
                else LorenzCiaTimer.subtracted(before, X901_SUB[init])
                end
      [counter, x9_icr(init), init == 0x0a ? 0x00 : 0x01]
    end

    def x909(init, before, _before_control)
      counter = if [3, 4].include?(init) then init - 2
                elsif init > 0x0d then init - 0x0d
                else LorenzCiaTimer.subtracted(before, X909_SUB[init])
                end
      started = init >= 0x16 || ((5...0x0a).cover?(init) && before >= 0x0b)
      [counter, x9_icr(init), started ? 0x09 : 0x08]
    end

    def x9_icr(init) = { 0x11 => 0x01 }.fetch(init) { init < 0x11 ? 0x81 : 0x00 }

    def x910(init, before, before_control) = [before, init < 0x0b ? 0x81 : 0x00, before_control & 0x09]

    def x911(init, before, before_control)
      counter = init == 0x0a ? before : LorenzCiaTimer.subtracted(before, 1)
      [counter, x91_icr(init, before), init == 0x0a ? 0x00 : before_control & 0x09]
    end

    def x919(init, before, _before_control)
      counter = [0, 0x0a, 0x0b].include?(init) ? before : LorenzCiaTimer.subtracted(before, 1)
      stop = init.zero? || (0x0a...0x0c).cover?(init) || before < 0x0a
      [counter, x91_icr(init, before), stop ? 0x08 : 0x09]
    end

    def x91_icr(init, before)
      return 0x81 if init < 0x0c || before < 5

      before == 5 ? 0x01 : 0x00
    end

    # The source's table search runs from the last entry down
    def special(keys, corrections, key)
      index = keys.rindex(key)
      index && corrections[index]
    end

    { x100: %i[x108], x110: %i[x118], x900: %i[x908], x910: %i[x918] }.each do |routine, labels|
      labels.each { |label| singleton_class.alias_method(label, routine) }
    end
  end
end
