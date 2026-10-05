# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module VICII
        # Reads a VIC-II module and puts it into badline's VIC.
        class Import
          def initialize(fields)
            @fields = fields
            read_beam
            read_counters
            read_sprites
          end

          def apply(computer)
            vic = computer.vic
            computer.address_bus.color_ram.tap do |ram|
              @color_ram.each_with_index { |value, offset| ram.poke(0xd800 + offset, value) }
            end
            load_registers(vic)
            position(vic)
            load_counters(vic)
            load_sprites(vic)
            vic.rebuild_sprite_ba
          end

          private

          def read_beam
            f = @fields
            f.skip(1)
            @registers = f.bytes(0x40)
            @cycle = f.dword
            f.skip(4)
            @line = f.dword
            @frame_start = f.flag?
            @irq_status = f.byte
            f.skip(4)
            @raster_match = f.flag?
            @character_buffer = f.bytes(40)
            @color_buffer = f.bytes(40)
            f.skip(1 + 4 + (65 * 8) + 4)
          end

          def read_counters
            f = @fields
            @bad_lines_enabled = f.flag?
            @collisions = [f.byte, f.byte]
            f.skip(1)
            @display = f.dword.zero?
            @vc_base, @vc, @rc, @vmli = Array.new(4) { f.dword }
            f.skip(4)
            @lp_low = f.flag?
            @lp_triggered = f.flag?
            f.skip(4 + 4 + 4 + 8)
            @fetch_d011 = f.byte
            f.skip(4)
            @display_bits = f.dword
            @dma_bits = f.byte
            f.skip(4)
            @vertical_border = f.flag?
            @vertical_armed = f.flag?
            @main_border = f.flag?
            f.skip(1)
            @color_ram = f.bytes(0x400)
          end

          # Each sprite's MC and MCBASE, and its expansion flip-flop as a bit.
          def read_sprites
            f = @fields
            @sprite_mc = Array.new(8, 0)
            @sprite_mcbase = Array.new(8, 0)
            @sprite_exp_ff = 0
            8.times do |n|
              f.skip(4)
              @sprite_mc[n] = f.byte
              @sprite_mcbase[n] = f.byte
              f.skip(1)
              @sprite_exp_ff |= 1 << n if f.flag?
              f.skip(4)
            end
          end

          def load_registers(vic)
            registers = vic.registers
            bytes = registers.bytes
            0x2f.times { |reg| bytes[reg] = @registers[reg] }
            bytes[0x19] = @irq_status & 0x0f
            bytes[0x1a] &= 0x0f
            bytes[0x1e], bytes[0x1f] = @collisions
            registers.update_irq_line
          end

          # Clocks the VIC alone from the start of the line to the cycle,
          # so the line's fetches and sprite checks have run.
          def position(vic)
            region = vic.region
            vic.restore_line(line(region.lines_per_frame))
            load_display_state(vic)
            column(region.cycles_per_line).times { vic.cycle! }
            registers = vic.registers
            registers.bytes[0x19] = @irq_status & 0x0f
            registers.bytes[0x1e], registers.bytes[0x1f] = @collisions
            registers.update_irq_line
          end

          # badline's column, VICE's cycle less one, with VICE's cycle 0
          # the last column of the line before (VICII.vice_cycle).
          def column(cycles_per_line) = @cycle.zero? ? cycles_per_line - 1 : @cycle - 1

          def line(lines)
            return @line unless @cycle.zero? && !@frame_start

            @line.zero? ? lines - 1 : @line - 1
          end

          def load_display_state(vic)
            vic.display_state.restore_counters([@vc_base, @vc, @rc, @vmli], @display, @bad_lines_enabled)
          end

          def load_counters(vic)
            load_display_state(vic)
            vic.character_buffer.replace(@character_buffer)
            vic.color_buffer.replace(@color_buffer)
            vic.restore_latches((@raster_match ? 1 : 0) | (@lp_low ? 2 : 0) | (@lp_triggered ? 4 : 0), @fetch_d011)
            vic.sequencer.restore_borders(@vertical_border, @vertical_armed, @main_border)
          end

          def load_sprites(vic)
            8.times do |n|
              bit = 1 << n
              vic.sprites[n].restore_counters(@sprite_mc[n], @sprite_mcbase[n], @sprite_exp_ff.anybits?(bit),
                                              @dma_bits.anybits?(bit), @display_bits.anybits?(bit))
            end
            vic.sprites.update_any_dma
          end
        end
      end
    end
  end
end
