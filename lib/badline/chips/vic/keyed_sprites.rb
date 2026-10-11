# frozen_string_literal: true

module Badline
  module Chips
    class VIC
      class Sprite
        # A sprite's fields under `prefix`: its DMA and display, MC, MCBASE
        # and the expansion flip-flop, the fetch in progress and the shift
        # register, and the line batch under `line_prefix` when `line` is
        # true.
        module KeyedState
          def save_fields(out, prefix, line_prefix)
            out.bool("#{prefix}dma", @dma).bool("#{prefix}display_on", @display_on).int("#{prefix}mcbase", @mcbase)
            out.int("#{prefix}mc", @mc).bool("#{prefix}exp_ff", @exp_ff).optional_int("#{prefix}crunched_mc",
                                                                                      @crunched_mc)
            out.int("#{prefix}bits", @bits).bool("#{prefix}row_ready", @row_ready)
            out.optional_int("#{prefix}prev_bits", @prev_bits).bool("#{prefix}first_byte_lost", @first_byte_lost)
            out.bool("#{prefix}blind", @blind).int("#{prefix}sr", @sr).int("#{prefix}latch", @latch)
            out.bool("#{prefix}mc_flop", @mc_flop).bool("#{prefix}xe_flop", @xe_flop)
            save_line_fields(out, line_prefix)
          end

          def load_fields(input, prefix, line_prefix, line)
            @dma = input.bool("#{prefix}dma", @dma)
            @display_on = input.bool("#{prefix}display_on", @display_on)
            @mcbase = input.masked("#{prefix}mcbase", @mcbase, 0x3f)
            @mc = input.masked("#{prefix}mc", @mc, 0x3f)
            @exp_ff = input.bool("#{prefix}exp_ff", @exp_ff)
            @crunched_mc = input.optional_int("#{prefix}crunched_mc")
            @bits = input.int("#{prefix}bits", @bits)
            @row_ready = input.bool("#{prefix}row_ready", @row_ready)
            @prev_bits = input.optional_int("#{prefix}prev_bits")
            @first_byte_lost = input.bool("#{prefix}first_byte_lost", @first_byte_lost)
            @blind = input.bool("#{prefix}blind", @blind)
            @sr = input.int("#{prefix}sr", @sr)
            @latch = input.int("#{prefix}latch", @latch)
            @mc_flop = input.bool("#{prefix}mc_flop", @mc_flop)
            @xe_flop = input.bool("#{prefix}xe_flop", @xe_flop)
            load_line_fields(input, line_prefix) if line
          end

          private

          def save_line_fields(out, prefix)
            out.int("#{prefix}show_from", @show_from).optional_int("#{prefix}stop_x", @stop_x)
            out.ints("#{prefix}codes", @codes).int("#{prefix}leftmost", @leftmost).int("#{prefix}span", @span)
            out.ints("#{prefix}reload_codes", @reload_codes).int("#{prefix}reload_leftmost", @reload_leftmost)
            out.int("#{prefix}reload_span", @reload_span)
          end

          def load_line_fields(input, prefix)
            @show_from = input.int("#{prefix}show_from", @show_from)
            @stop_x = input.optional_int("#{prefix}stop_x")
            input.ints_into("#{prefix}codes", @codes)
            @leftmost = input.int("#{prefix}leftmost", @leftmost)
            @span = input.int("#{prefix}span", @span)
            input.ints_into("#{prefix}reload_codes", @reload_codes)
            @reload_leftmost = input.int("#{prefix}reload_leftmost", @reload_leftmost)
            @reload_span = input.int("#{prefix}reload_span", @reload_span)
          end
        end

        include KeyedState

        class InternalBus
          # The sprites' internal bus, under `prefix`.
          module KeyedState
            def save_fields(out, prefix)
              out.int("#{prefix}lines", @lines).int("#{prefix}ghost", @ghost).ints("#{prefix}value", @value)
              out.ints("#{prefix}line", @line)
            end

            def load_fields(input, prefix)
              @lines = input.int("#{prefix}lines", @lines)
              @ghost = input.byte("#{prefix}ghost", @ghost)
              input.ints_into("#{prefix}value", @value)
              input.ints_into("#{prefix}line", @line)
            end
          end

          include KeyedState
        end
      end

      class Collisions
        # The read-clear timing at the beam, and the line's coverage under
        # `line_prefix` when `line` is true.
        module KeyedState
          def save_fields(out, line_prefix)
            out.int("collisions.cleared_sprite", @cleared_sprite).int("collisions.cleared_data", @cleared_data)
            out.bytes("#{line_prefix}hits", @hits).int("#{line_prefix}folded", @folded)
          end

          def load_fields(input, line_prefix, line)
            @cleared_sprite = input.int("collisions.cleared_sprite", @cleared_sprite)
            @cleared_data = input.int("collisions.cleared_data", @cleared_data)
            return unless line

            input.bytes_into("#{line_prefix}hits", @hits)
            @folded = input.int("#{line_prefix}folded", @folded)
          end
        end

        include KeyedState
      end

      class RegisterLog
        # The line's sprite register writes, under `prefix`: the entries as
        # pixel, register and value in turn, the seed with -1 for a register
        # not logged, and the next pixel as -1 past the last entry.
        module KeyedState
          def save_fields(out, prefix)
            out.ints("#{prefix}entries", @entries.flatten)
            out.ints("#{prefix}seed", @seed.map { |value| value.nil? ? -1 : value })
            out.ints("#{prefix}values", @values).int("#{prefix}cursor", @cursor)
            out.int("#{prefix}next_x", @next_x.infinite? ? -1 : @next_x)
          end

          def load_fields(input, prefix)
            @entries.replace(input.ints("#{prefix}entries", []).each_slice(3).to_a)
            @seed.replace(input.ints("#{prefix}seed", []).map { |value| value.negative? ? nil : value })
            input.ints_into("#{prefix}values", @values)
            @cursor = input.int("#{prefix}cursor", @cursor)
            next_x = input.int("#{prefix}next_x", 0)
            @next_x = next_x.negative? ? Float::INFINITY : next_x
          end
        end

        include KeyedState
      end

      class Sprites
        # The sprites under sprite0. to sprite7., their bus under sbus.,
        # the collisions, and the line batch under `line_prefix`: the
        # window's colours and priorities, the span touched, the pixels
        # carried into the next line, the register log. Whether any DMA
        # runs comes from the sprites on load.
        module KeyedState
          def save_fields(out, line_prefix)
            @sprites.each do |sprite|
              sprite.save_fields(out, "sprite#{sprite.index}.", "#{line_prefix}sprite#{sprite.index}.")
            end
            @bus.save_fields(out, "sbus.")
            @collisions.save_fields(out, "#{line_prefix}collisions.")
            out.bool("#{line_prefix}carried", @carried).int("#{line_prefix}lo", @lo).int("#{line_prefix}hi", @hi)
            out.int("#{line_prefix}sequenced", @sequenced).bytes("#{line_prefix}win_color", @win_color)
            out.ints("#{line_prefix}win_priority", @win_priority.map { |set| set ? 1 : 0 })
            out.ints("#{line_prefix}palette", @palette).bool("#{line_prefix}stopped_dma", @stopped_dma)
            save_carry_fields(out, "#{line_prefix}carry", @carry)
            save_carry_fields(out, "#{line_prefix}carry_next", @carry_next)
            @log.save_fields(out, "#{line_prefix}log.")
          end

          def load_fields(input, line_prefix, line)
            @sprites.each do |sprite|
              sprite.load_fields(input, "sprite#{sprite.index}.", "#{line_prefix}sprite#{sprite.index}.", line)
            end
            @bus.load_fields(input, "sbus.")
            @collisions.load_fields(input, "#{line_prefix}collisions.", line)
            load_line_fields(input, line_prefix) if line
          end

          def restored! = update_any_dma

          private

          def load_line_fields(input, prefix)
            @carried = input.bool("#{prefix}carried", @carried)
            @lo = input.int("#{prefix}lo", @lo)
            @hi = input.int("#{prefix}hi", @hi)
            @sequenced = input.int("#{prefix}sequenced", @sequenced)
            input.bytes_into("#{prefix}win_color", @win_color)
            priority = input.ints("#{prefix}win_priority", @win_priority.map { |set| set ? 1 : 0 })
            @win_priority.each_index { |index| @win_priority[index] = priority.fetch(index, 0) == 1 }
            input.ints_into("#{prefix}palette", @palette)
            @stopped_dma = input.bool("#{prefix}stopped_dma", @stopped_dma)
            load_carry_fields(input, "#{prefix}carry", @carry)
            load_carry_fields(input, "#{prefix}carry_next", @carry_next)
            @log.load_fields(input, "#{prefix}log.")
          end

          # Each sprite's carried pixels as x, colour and priority (0 or 1)
          # in turn.
          def save_carry_fields(out, prefix, carry)
            carry.each_with_index do |pixels, index|
              values = []
              pixels.each_slice(3) { |x, color, priority| values.push(x, color, priority ? 1 : 0) }
              out.ints("#{prefix}#{index}", values)
            end
          end

          def load_carry_fields(input, prefix, carry)
            carry.each_with_index do |pixels, index|
              pixels.clear
              input.ints("#{prefix}#{index}", []).each_slice(3) do |x, color, priority|
                pixels.push(x, color, priority == 1)
              end
            end
          end
        end

        include KeyedState
      end
    end
  end
end
