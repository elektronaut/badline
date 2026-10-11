# frozen_string_literal: true

module Badline
  module Chips
    class VICI
      class Sound
        # The sound's fields in a keyed snapshot module, under `prefix`:
        # the voices' shift registers, the noise LFSR, the level, and when
        # each voice next shifts, in cycles from the machine's clock, with
        # how far behind the clock the voices last ran. The volume and the
        # voices' frequencies come from the VIC's registers on load.
        module KeyedState
          def save_fields(out, prefix)
            now = @clock.cycles
            run_to(now)
            out.ints("#{prefix}shift_registers", @shift_registers).int("#{prefix}lfsr", @lfsr)
            out.int("#{prefix}level", @level).int("#{prefix}ran_ago", now - @time)
            out.ints("#{prefix}next_shifts", @next_shifts.map { |due| due - now })
          end

          def load_fields(input, prefix)
            now = @clock.cycles
            input.ints_into("#{prefix}shift_registers", @shift_registers)
            @lfsr = input.masked("#{prefix}lfsr", @lfsr, 0xffff)
            @level = input.int("#{prefix}level", @level)
            @time = now - input.int("#{prefix}ran_ago", now - @time)
            relative = input.ints("#{prefix}next_shifts", @next_shifts.map { |due| due - now })
            VOICES.times { |voice| @next_shifts[voice] = now + relative.fetch(voice, 0) }
          end

          # $900A to $900E as written.
          def restore_registers(registers)
            @volume = registers[0x0e] & 0x0f
            VOICES.times do |voice|
              value = registers[0x0a + voice]
              @frequencies[voice] = value & 0x7f
              @enabled[voice] = value >= 0x80
            end
          end
        end

        include KeyedState
      end

      class Painter
        # The lines' fetches and the line going out, as this painter lays
        # them out (VICI::LINE_LAYOUT), and the picture.
        module KeyedState
          def save_fields(out)
            out.int("line.row", @row).int("line.painted", @painted).bool("line.written", @written)
            out.bytes("line.patterns", @patterns).bytes("line.colors", @colors)
            out.ints("line.counts", @counts).ints("line.starts", @starts).bytes("display", @display)
          end

          def load_fields(input, layout)
            input.bytes_into("display", @display)
            return unless layout

            @row = input.int("line.row", @row)
            @painted = input.int("line.painted", @painted)
            @written = input.bool("line.written", @written)
            input.bytes_into("line.patterns", @patterns)
            input.bytes_into("line.colors", @colors)
            input.ints_into("line.counts", @counts)
            input.ints_into("line.starts", @starts)
          end

          # The colours as $900E and $900F hold them, every line to be
          # painted afresh, and the whole display changed.
          def restored!(registers)
            @border = registers[0x0f] & 0x07
            @background = registers[0x0f] >> 4
            @reverse = registers[0x0f].nobits?(0x08)
            @aux = registers[0x0e] >> 4
            @stale.fill(true)
            @memo_keys.fill(-1)
            @dirty_lines.fill(true)
          end
        end

        include KeyedState
      end

      # The shape of the painter's per-line fields. A snapshot whose
      # line.layout differs leaves them at power-on.
      LINE_LAYOUT = 1

      # The VIC-I's fields in a keyed snapshot module (Snapshot::Keyed): the
      # registers, the beam, the text window's counters and the fetch in
      # flight, the painter's lines under line.*, the picture, and the sound
      # under sound.* What the registers decode to, where the line's fetches
      # end and the next event are worked out on load.
      module KeyedState
        def save_fields(out)
          out.bytes("registers", @registers).int("raster", @rasterline).int("column", @column)
          out.bool("window_open", @window_open).bool("window_done", @window_done).int("row_start", @row_start)
          out.int("matrix", @matrix).int("char_line", @char_line).int("text_rows", @text_rows)
          out.int("fetch_from", @fetch_from).int("fetched", @fetched).int("code", @code)
          out.int("line.layout", LINE_LAYOUT)
          @painter.save_fields(out)
          @sound&.save_fields(out, "sound.")
          out
        end

        def load_fields(input)
          input.bytes_into("registers", @registers)
          @rasterline = input.int("raster", @rasterline)
          @column = input.int("column", @column)
          @window_open = input.bool("window_open", @window_open)
          @window_done = input.bool("window_done", @window_done)
          @row_start = input.int("row_start", @row_start)
          @matrix = input.int("matrix", @matrix)
          @char_line = input.int("char_line", @char_line)
          @text_rows = input.int("text_rows", @text_rows)
          @fetch_from = input.int("fetch_from", @fetch_from)
          @fetched = input.int("fetched", @fetched)
          @code = input.byte("code", @code)
          @painter.load_fields(input, input.int("line.layout", 0) == LINE_LAYOUT)
          @sound&.load_fields(input, "sound.")
        end

        def restored!
          @origin_x = @registers[0] & 0x7f
          @columns = @registers[2] & 0x7f
          @origin_y = @registers[1]
          rows_written(@registers[3])
          bases_written
          @slot = @rasterline * Painter::SLOTS
          @fetch_to = 0
          fetches_end if @window_open
          schedule
          @painter.restored!(@registers)
          @sound&.restore_registers(@registers)
        end
      end

      include KeyedState
    end
  end
end
