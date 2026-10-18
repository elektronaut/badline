# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module CBM2
        # The mains on TPI1's I0. xcbm2 saves no mains: it ticks it once a
        # frame of its CRTC, as vertical sync ends, whatever the mains is
        # set to. A machine read from its snapshot has its mains' next
        # falling edge where xcbm2's tick would come, and runs it at its own
        # 50 or 60 Hz from there. A snapshot written for xcbm2 ticks where
        # its CRTC says.
        module Mains
          # The cycle of the line where vertical sync ends that the tick
          # latches on, counted as badline's CRTC counts columns.
          TICK_COLUMN = 0

          module_function

          # The cycles to the mains' next falling edge for a CRTC whose
          # BL-CRTC fields `crtc` holds.
          def next_tick(crtc)
            registers = crtc.bytes("registers", "".b).bytes
            regs = Array.new(Chips::CRTC::MASKS.length) { |index| registers[index] || 0 }
            line_cycles = regs[0] + 1
            lines = regs[9] + 1
            rows = regs[4] + 1
            frame_lines = (rows * lines) + regs[5]
            line = crtc.int("line", 0)
            line += crtc.bool("adjusting", false) ? rows * lines : crtc.int("row", 0) * lines
            tick_line = ((regs[7] * lines) + Chips::CRTC::VSYNC_LINES) % frame_lines
            frame = line_cycles * frame_lines
            cycles = ((tick_line * line_cycles) + TICK_COLUMN - ((line * line_cycles) + crtc.int("column", 0))) % frame
            cycles.zero? ? frame : cycles
          end

          # The BL-MACHINE mains fields for a mains `half_period` cycles high
          # and as long low, whose next falling edge is `cycles` away.
          def write(out, cycles, half_period)
            high = cycles <= half_period
            countdown = high ? cycles : [cycles - half_period, half_period].min
            out.int("mains_countdown", countdown).bool("mains_high", high)
            high
          end
        end
      end
    end
  end
end
