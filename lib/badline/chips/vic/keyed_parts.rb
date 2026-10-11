# frozen_string_literal: true

module Badline
  module Chips
    class VIC
      class Registers
        # The registers as the VIC holds them. The IRQ line comes from
        # $D019 and $D01A on load.
        module KeyedState
          def save_fields(out)
            out.bytes("registers", @bytes)
          end

          def load_fields(input)
            input.bytes_into("registers", @bytes)
          end

          def restored! = update_irq_line
        end

        include KeyedState
      end

      class DisplayState
        # The video counters, the row counter, display or idle state, the
        # bad line conditions and BA.
        module KeyedState
          def save_fields(out)
            out.int("vc_base", @vc_base).int("vc", @vc).int("vmli", @vmli).int("rc", @rc).bool("display_state", @display)
            out.bool("bad_lines_enabled", @bad_lines_enabled).bool("matched", @matched).optional_int("ba", @ba)
            out.int("line_bits", @line_bits).bool("den_line", @den_line).bool("in_window", @in_window)
          end

          def load_fields(input)
            @vc_base = input.masked("vc_base", @vc_base, 0x3ff)
            @vc = input.masked("vc", @vc, 0x3ff)
            @vmli = input.int("vmli", @vmli)
            @rc = input.masked("rc", @rc, 0x07)
            @display = input.bool("display_state", @display)
            @bad_lines_enabled = input.bool("bad_lines_enabled", @bad_lines_enabled)
            @matched = input.bool("matched", @matched)
            @ba = input.optional_int("ba")
            @line_bits = input.int("line_bits", @line_bits)
            @den_line = input.bool("den_line", @den_line)
            @in_window = input.bool("in_window", @in_window)
          end
        end

        include KeyedState
      end

      class GraphicsShifter
        # The pipeline between the g-access and the pixels, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}next_ecm_bmm", @next_ecm_bmm).int("#{prefix}black_below", @black_below)
            out.ints("#{prefix}colors", @colors).ints("#{prefix}fg", @fg.map { |set| set ? 1 : 0 })
            out.int("#{prefix}gbuf", @gbuf).int("#{prefix}vbuf", @vbuf).int("#{prefix}cbuf", @cbuf)
            out.int("#{prefix}flop", @flop).int("#{prefix}pixel", @pixel).int("#{prefix}mode_lookup", @mode_lookup)
            out.int("#{prefix}mode_read", @mode_read).bool("#{prefix}late_mcm", @late_mcm)
            out.bool("#{prefix}late_read", @late_read)
          end

          def load_fields(input, prefix)
            @next_ecm_bmm = input.int("#{prefix}next_ecm_bmm", @next_ecm_bmm)
            @black_below = input.int("#{prefix}black_below", @black_below)
            input.ints_into("#{prefix}colors", @colors)
            fg = input.ints("#{prefix}fg", @fg.map { |set| set ? 1 : 0 })
            @fg.each_index { |index| @fg[index] = fg.fetch(index, 0) == 1 }
            @gbuf = input.int("#{prefix}gbuf", @gbuf)
            @vbuf = input.int("#{prefix}vbuf", @vbuf)
            @cbuf = input.int("#{prefix}cbuf", @cbuf)
            @flop = input.int("#{prefix}flop", @flop)
            @pixel = input.int("#{prefix}pixel", @pixel)
            @mode_lookup = input.int("#{prefix}mode_lookup", @mode_lookup)
            @mode_read = input.int("#{prefix}mode_read", @mode_read)
            @late_mcm = input.bool("#{prefix}late_mcm", @late_mcm)
            @late_read = input.bool("#{prefix}late_read", @late_read)
          end
        end

        include KeyedState
      end

      class BorderMask
        # The line's border coverage, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.ints("#{prefix}groups", @groups).ints("#{prefix}mask", @mask.map { |set| set ? 1 : 0 })
            out.bytes("#{prefix}snapshot", @snapshot)
          end

          def load_fields(input, prefix)
            input.ints_into("#{prefix}groups", @groups)
            mask = input.ints("#{prefix}mask", @mask.map { |set| set ? 1 : 0 })
            @mask.each_index { |index| @mask[index] = mask.fetch(index, 0) == 1 }
            input.bytes_into("#{prefix}snapshot", @snapshot)
          end
        end

        include KeyedState
      end

      class ColorPatches
        # The line's colour writes, four values to a patch, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.ints("#{prefix}patches", @patches.flatten)
          end

          def load_fields(input, prefix)
            values = input.ints("#{prefix}patches", [])
            @patches.replace(values.each_slice(4).to_a)
          end
        end

        include KeyedState
      end

      class Sequencer
        # The sequencer's fields: the border flip-flops and compares, the
        # pixel pipeline and the shifter, with the line batch under
        # `line_prefix` when `line` is true. Foreground masks go as text:
        # "shifter", or the mode table and the data byte.
        module KeyedState
          def save_fields(out, line_prefix)
            out.bool("first_csel", @first_csel).optional_int("left_vertical_border", left_vertical_code)
            out.ints("cur_colors", @cur_colors).text("cur_fg", fg_name(@cur_fg))
            out.ints("prev_colors", @prev_colors).text("prev_fg", fg_name(@prev_fg))
            out.bool("vertical_border", @vertical_border).bool("vertical_armed", @vertical_armed)
            out.bool("main_border", @main_border).int("xscroll", @xscroll).int("last_shift", @last_shift)
            out.int("last_mode", @last_mode).bool("settling", @settling).bool("prev_fresh", @prev_fresh)
            out.bool("check", @check)
            @shifter.save_fields(out, "shifter.")
            out.int("#{line_prefix}number", @line).bytes("#{line_prefix}colors", @colors)
            out.ints("#{line_prefix}fg", @fg.map { |set| set ? 1 : 0 })
            @border_mask.save_fields(out, "#{line_prefix}border.")
            @color_patches.save_fields(out, line_prefix)
          end

          def load_fields(input, line_prefix, line)
            @first_csel = input.bool("first_csel", @first_csel)
            left = input.optional_int("left_vertical_border")
            @left_vertical_border = left.nil? ? nil : left == 1
            input.ints_into("cur_colors", @cur_colors)
            @cur_fg = fg_named(input.text("cur_fg", fg_name(@cur_fg)))
            input.ints_into("prev_colors", @prev_colors)
            @prev_fg = fg_named(input.text("prev_fg", fg_name(@prev_fg)))
            load_pipeline_fields(input)
            @shifter.load_fields(input, "shifter.")
            load_line_fields(input, line_prefix) if line
          end

          private

          def left_vertical_code
            left = @left_vertical_border
            return nil if left.nil?

            left ? 1 : 0
          end

          def load_pipeline_fields(input)
            @vertical_border = input.bool("vertical_border", @vertical_border)
            @vertical_armed = input.bool("vertical_armed", @vertical_armed)
            @main_border = input.bool("main_border", @main_border)
            @xscroll = input.masked("xscroll", @xscroll, 0x07)
            @last_shift = input.int("last_shift", @last_shift)
            @last_mode = input.int("last_mode", @last_mode)
            @settling = input.bool("settling", @settling)
            @prev_fresh = input.bool("prev_fresh", @prev_fresh)
            @check = input.bool("check", @check)
          end

          def load_line_fields(input, line_prefix)
            @line = input.int("#{line_prefix}number", @line)
            input.bytes_into("#{line_prefix}colors", @colors)
            fg = input.ints("#{line_prefix}fg", @fg.map { |set| set ? 1 : 0 })
            @fg.each_index { |index| @fg[index] = fg.fetch(index, 0) == 1 }
            @border_mask.load_fields(input, "#{line_prefix}border.")
            @color_patches.load_fields(input, line_prefix)
          end

          def fg_name(pattern)
            code = fg_code(pattern)
            return "shifter" if code == SavedState::FG_SHIFTER
            return "hires:#{code}" if code < SavedState::PAIR_CODES

            "pair:#{code - SavedState::PAIR_CODES}"
          end

          def fg_named(name)
            return @shifter.fg if name == "shifter"

            table, number = name.split(":")
            index = number.to_i
            return GraphicsMode::PAIR_FG.fetch(index.clamp(0, GraphicsMode::PAIR_FG.length - 1)) if table == "pair"

            GraphicsMode::HIRES_FG.fetch(index.clamp(0, GraphicsMode::HIRES_FG.length - 1))
          end
        end

        include KeyedState
      end
    end
  end
end

require "badline/chips/vic/keyed_sprites"
require "badline/chips/vic/keyed_state"
