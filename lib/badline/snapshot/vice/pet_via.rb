# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # VIA 2.2, the 6522 at $E840: port A's and port B's output and
        # direction registers, timer 1's latch and counter, timer 2's low
        # and high latch, the value it was last loaded with and its counter,
        # which timers will set their interrupt flag (timer 1 in bit 7,
        # timer 2 in bit 6 while it counts cycles), the shift register, the
        # ACR, the PCR, the interrupt flags and enable mask, timer 1's level
        # on PB7 in bit 7, the shift register's clock ticks into its byte,
        # CA2's level in bit 7, and whether timer 2's next underflow sets
        # its flag. xpet saves each counter as a read on the next cycle
        # finds it, where badline's holds it before that cycle counts.
        #
        # Written: timer 2's high latch and the value it was loaded with,
        # which badline doesn't keep, as xpet has them before a program
        # loads it, or while the shift register clocks off it, as its low
        # byte reloads. Free-running, the shift register's ticks are only
        # whether CB1 is low.
        #
        # Read: the registers and both timers with their latches, as they
        # count from the next cycle, and the shift register where its clock
        # ticks are. A load or reload under way, a shift clock tick due off
        # timer 2 and the latched ports start afresh, and CB2's level
        # follows from the PCR.
        module VIA
          NAME = "VIA"
          MAJOR = 2
          MINOR = 2
          T1_ARMED = 0x80
          T2_TIMED = 0x40
          LEVELS = 0x60
          # The shift register's clock ticks a byte takes, which an idle
          # register's count stands at.
          TICKS = 16
          SIZE = 28
          # The shift register's modes that clock off timer 2.
          T2_SHIFTS = [1, 4, 5].freeze

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          # The VIA's module, under `name`, from its BL-VIA fields in `input`.
          def export(input, name = NAME)
            fields = FieldWriter.new
            %w[ora ddra orb ddrb].each { |key| fields.byte(input.int(key, 0)) }
            fields.word(input.int("t1.latch", 0xffff)).word(timer1(input))
            t2 = timer2(input)
            latch_low = input.int("t2.latch_low", 0xff)
            fields.byte(latch_low).byte(0xff).word(shifting?(input) ? (t2 & 0xff00) | latch_low : 0xffff).word(t2)
            fields.byte(armed(input)).byte(input.int("sr.data", 0))
            fields.byte(input.int("acr", 0)).byte(input.int("pcr", 0))
            fields.byte(input.int("ifr.flags", 0)).byte(input.int("ifr.enable", 0))
            fields.byte(input.bool("t1.pb7", true) ? 0x80 : 0)
            fields.byte(ticks(input))
            fields.byte(LEVELS | (input.bool("ca.c2_output", true) ? 0x80 : 0)).zeros(2)
            fields.byte(input.bool("t2.armed", false) ? 1 : 0).zeros(2).section(name, MAJOR, MINOR)
          end

          # Timer 1's counter as a read on the next cycle finds it: as it
          # stands while a load holds it, the latch while it reloads, and one
          # less otherwise.
          def timer1(input)
            counter = input.int("t1.counter", 0xffff)
            return counter if input.bool("t1.hold", false)
            return input.int("t1.latch", 0xffff) if input.bool("t1.reload", false)

            (counter - 1) & 0xffff
          end

          # Timer 2's counter as a read on the next cycle finds it: as it
          # stands while it counts pulses or a load holds it, and one less
          # otherwise.
          def timer2(input)
            counter = input.int("t2.counter", 0xffff)
            return counter if input.bool("t2.hold", false) || input.bool("t2.counting_pulses", false)

            (counter - 1) & 0xffff
          end

          # The shift register's clock ticks into its byte: two a bit, the
          # first one dropping CB1, TICKS when idle. Free-running, its bits
          # never run out, and only whether CB1 is low counts.
          def ticks(input)
            bits = input.int("sr.bits", 0)
            return TICKS if bits.zero?

            low = input.bool("sr.clock", true) ? 0 : 1
            return low if input.int("sr.mode", 0) == 4

            ((8 - bits) * 2) + low
          end

          # The shift register from its mode, data and the ticks into its
          # byte (#ticks), with the last bit put out on CB2, or CB2 high
          # as it is at power-on while the register is off.
          def shift_register(out, mode, data, ticks)
            ticks = [ticks, TICKS].min
            bits = ticks == TICKS ? 0 : 8 - (ticks / 2)
            bits = 8 if mode == 4 && ticks < TICKS
            out.int("sr.mode", mode).int("sr.data", data).int("sr.bits", bits).int("sr.delay", 0)
            out.bool("sr.clock", ticks.even?).bool("sr.cb2", mode.zero? || ticks.zero? || data.anybits?(0x01))
          end

          # Whether the shift register clocks off timer 2.
          def shifting?(input) = T2_SHIFTS.include?((input.int("acr", 0) >> 2) & 0x07)

          # Timer 2 sets its flag, or clocks the shift register, while it
          # counts cycles.
          def armed(input)
            pulses = input.bool("t2.count_pulses", false)
            timed = !pulses && (input.bool("t2.armed", false) || shifting?(input))
            (input.bool("t1.armed", false) ? T1_ARMED : 0) | (timed ? T2_TIMED : 0)
          end

          # The registers, the timers and the control lines by their BL-VIA
          # keys, in a keyed module's writer.
          def import(section, out)
            bytes = FieldReader.new(section).bytes(SIZE)
            acr = bytes[0x10]
            pcr = bytes[0x11]
            out.int("ora", bytes[0]).int("ddra", bytes[1]).int("orb", bytes[2]).int("ddrb", bytes[3])
            out.int("acr", acr).int("pcr", pcr)
            timers(out, bytes, acr)
            shift_register(out, (acr >> 2) & 0x07, bytes[0x0f], bytes[0x15])
            out.int("ifr.flags", bytes[0x12] & 0x7f).int("ifr.enable", bytes[0x13] & 0x7f)
            control_lines(out, "ca.", pcr & 0x0f, bytes[0x16].anybits?(0x80))
            control_lines(out, "cb.", pcr >> 4, true)
          end

          def timers(out, bytes, acr)
            out.int("t1.latch", bytes[4] | (bytes[5] << 8)).int("t1.counter",
                                                                ((bytes[6] | (bytes[7] << 8)) + 1) & 0xffff)
            out.bool("t1.hold", false)
            out.bool("t1.reload", false).bool("t1.armed", bytes[0x0e].anybits?(T1_ARMED))
            out.bool("t1.pb7", bytes[0x14].anybits?(0x80))
            pulses = acr.anybits?(0x20)
            t2 = bytes[0x0c] | (bytes[0x0d] << 8)
            out.int("t2.latch_low", bytes[8]).int("t2.counter", pulses ? t2 : (t2 + 1) & 0xffff).bool("t2.hold", false)
            out.bool("t2.low_reload", false).bool("t2.low_underflowed", false)
            out.bool("t2.armed", bytes[0x19].anybits?(0x01))
            out.bool("t2.count_pulses", pulses).bool("t2.counting_pulses", pulses)
          end

          # A handshake under way holds C2 low.
          def control_lines(out, prefix, control, c2_high)
            mode = control >> 1
            handshake_low = mode == 4 && !c2_high
            output = case mode
                     when 4 then !handshake_low
                     when 6 then false
                     else true
                     end
            out.int("#{prefix}control", control).bool("#{prefix}handshake_low", handshake_low)
            out.int("#{prefix}pulse", 0).bool("#{prefix}c2_output", output)
          end
        end
      end
    end
  end
end
