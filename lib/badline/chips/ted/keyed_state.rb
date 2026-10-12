# frozen_string_literal: true

module Badline
  module Chips
    class TED
      class Sound
        # The sound's fields in a keyed snapshot module (Snapshot::Keyed,
        # BL-TEDSOUND): each voice's output and when it next toggles, in
        # cycles from the machine's clock, absent while it never will, the
        # noise's shift register, and how far behind the clock the voices
        # last ran. The frequencies, the volume and the reload bit come from
        # the TED's registers on load (#restored!), and the output's level
        # from those.
        module KeyedState
          def save_fields(out)
            now = @clock.cycles
            run_to(now)
            VOICES.times do |voice|
              due = @next_toggles[voice]
              out.int("voice#{voice + 1}.phase", @phases[voice])
              out.optional_int("voice#{voice + 1}.toggle_in", due >= NEVER ? nil : due - now)
            end
            out.int("noise", @noise).int("ran_ago", now - @time)
          end

          def load_fields(input)
            now = @clock.cycles
            VOICES.times do |voice|
              @phases[voice] = input.masked("voice#{voice + 1}.phase", @phases[voice], 0x01)
              due = input.optional_int("voice#{voice + 1}.toggle_in")
              @next_toggles[voice] = due.nil? ? NEVER : now + due
            end
            @noise = input.byte("noise", @noise)
            @time = now - input.int("ran_ago", now - @time)
          end

          # The frequencies, the volume and the reload bit as `ted`'s
          # registers $FF0E-$FF12 hold them, and the level they give.
          def restored!(ted)
            @frequencies[0] = ted.peek(0xff0e) | ((ted.peek(0xff12) & 0x03) << 8)
            @frequencies[1] = ted.peek(0xff0f) | ((ted.peek(0xff10) & 0x03) << 8)
            VOICES.times { |voice| @intervals[voice] = interval_for(@frequencies[voice]) }
            control = ted.peek(0xff11)
            @control = control
            @reloading = control >= 0x80
            @volume = [control & 0x0f, 8].min
            @level = level_now
          end
        end

        include KeyedState
      end

      # The DMA a line makes, as a snapshot names it, in Beam's order.
      DMA_KINDS = %w[none attributes pointers].freeze

      # The shape of the line going out, as the picture paints it. A
      # snapshot whose line.layout differs repaints the line from its
      # start.
      LINE_LAYOUT = 1

      # The TED's fields in a keyed snapshot module (Snapshot::Keyed,
      # BL-TED): the registers as written, the interrupt flags, the keyboard
      # latch, the blink counter, the timers, the beam and the clock it gave
      # the CPU last, the fetches' buffers and counters, and the picture:
      # where the scanline is, whether the window is open, how far the line
      # going out is painted (line.*), and the picture itself. The interrupt
      # mask and the raster compare come from $FF0A and $FF0B on load.
      module KeyedState
        def save_fields(out)
          out.bytes("registers", @registers).int("interrupt_flags", @interrupt_flags).int("key_latch", @key_latch)
          out.int("blink", @blink).bool("blink_on", @blink_on)
          save_timer_fields(out)
          out.int("column", @column).int("line", @line).bool("ba", @ba_low).int("cpu_slots", @cpu_slots)
          save_fetch_fields(out)
          out.int("scanline", @scanline).bool("window_open", @window_open)
          out.int("line.layout", LINE_LAYOUT).int("line.painted", @painted).bytes("display", @display)
        end

        def load_fields(input)
          input.bytes_into("registers", @registers)
          @interrupt_flags = input.byte("interrupt_flags", @interrupt_flags)
          @key_latch = input.byte("key_latch", @key_latch)
          @blink = input.masked("blink", @blink, 0x0f)
          @blink_on = input.bool("blink_on", @blink_on)
          load_timer_fields(input)
          @column = input.int("column", @column) % Beam::CYCLES_PER_LINE
          @line = input.masked("line", @line, 0x1ff)
          @ba_low = input.bool("ba", @ba_low)
          @cpu_slots = input.int("cpu_slots", @cpu_slots).clamp(0, 2)
          load_fetch_fields(input)
          @scanline = input.int("scanline", @scanline)
          @window_open = input.bool("window_open", @window_open)
          load_line_fields(input)
          input.bytes_into("display", @display)
        end

        # The interrupt mask and the raster compare from $FF0A and $FF0B,
        # and every line of the picture changed.
        def restored!
          mask = @registers[0x0a]
          @interrupt_mask = mask & 0x5f
          @raster_compare = ((mask & 0x01) << 8) | @registers[0x0b]
          @dirty_lines.fill(true)
        end

        private

        def save_timer_fields(out)
          3.times do |index|
            out.int("timer#{index + 1}.count", @timer_counts[index])
            out.bool("timer#{index + 1}.running", @timer_running[index])
          end
          out.int("timer1.reload", @timer1_reload)
        end

        def load_timer_fields(input)
          3.times do |index|
            @timer_counts[index] = input.word("timer#{index + 1}.count", @timer_counts[index])
            @timer_running[index] = input.bool("timer#{index + 1}.running", @timer_running[index])
          end
          @timer1_reload = input.word("timer1.reload", @timer1_reload)
        end

        def save_fetch_fields(out)
          out.bytes("fetch.patterns", @patterns).bytes("fetch.pointers", @pointers)
          out.bytes("fetch.attributes", @attributes).bytes("fetch.next_attributes", @fetched_attributes)
          out.int("fetch.char_position", @char_position).int("fetch.line_position", @line_position)
          out.int("fetch.row_line", @row_line).bool("fetch.row_active", @row_active)
          out.text("fetch.dma", DMA_KINDS.fetch(@dma_kind)).bool("fetch.patterns_on", @pattern_fetches)
        end

        def load_fetch_fields(input)
          input.bytes_into("fetch.patterns", @patterns)
          input.bytes_into("fetch.pointers", @pointers)
          input.bytes_into("fetch.attributes", @attributes)
          input.bytes_into("fetch.next_attributes", @fetched_attributes)
          @char_position = input.masked("fetch.char_position", @char_position, 0x3ff)
          @line_position = input.masked("fetch.line_position", @line_position, 0x3ff)
          @row_line = input.masked("fetch.row_line", @row_line, 0x07)
          @row_active = input.bool("fetch.row_active", @row_active)
          @dma_kind = DMA_KINDS.index(input.choice("fetch.dma", DMA_KINDS, DMA_KINDS.fetch(@dma_kind))) || 0
          @pattern_fetches = input.bool("fetch.patterns_on", @pattern_fetches)
        end

        def load_line_fields(input)
          line = input.int("line.layout", 0) == LINE_LAYOUT
          input.adjust("line in progress from another renderer, restarted") unless line || input.missing?
          @painted = line ? input.int("line.painted", @painted).clamp(0, Picture::WIDTH) : 0
        end
      end

      include KeyedState
    end
  end
end
