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
            vic.send(:rebuild_sprite_ba)
          end

          private

          def read_beam
            f = @fields
            f.skip(1)
            @registers = f.bytes(0x40)
            @cycle = f.dword
            f.skip(4)
            @line = f.dword
            f.skip(1)
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
            @borders = [f.flag?, f.flag?, f.flag?]
            f.skip(1)
            @color_ram = f.bytes(0x400)
          end

          def read_sprites
            @sprites = Array.new(8) do
              f = @fields
              f.skip(4)
              counters = { mc: f.byte, mcbase: f.byte }
              f.skip(1)
              counters.merge(exp_ff: f.flag?).tap { f.skip(4) }
            end
          end

          def load_registers(vic)
            registers = vic.instance_variable_get(:@registers)
            bytes = registers.bytes
            0x2f.times { |reg| bytes[reg] = @registers[reg] }
            bytes[0x19] = @irq_status & 0x0f
            bytes[0x1a] &= 0x0f
            bytes[0x1e], bytes[0x1f] = @collisions
            registers.send(:update_irq_line)
          end

          # Clocks the VIC alone from the start of the line to the cycle,
          # so the line's fetches and sprite checks have run.
          def position(vic)
            vic.instance_variable_set(:@rasterline, @line)
            vic.instance_variable_set(:@column, 0)
            load_display_state(vic)
            @cycle.times { vic.cycle! }
            vic.instance_variable_get(:@registers).tap do |registers|
              registers.bytes[0x19] = @irq_status & 0x0f
              registers.bytes[0x1e], registers.bytes[0x1f] = @collisions
              registers.send(:update_irq_line)
            end
          end

          def load_display_state(vic)
            state = vic.instance_variable_get(:@display_state)
            { vc_base: @vc_base, vc: @vc, rc: @rc, vmli: @vmli, display: @display,
              bad_lines_enabled: @bad_lines_enabled }.each do |name, value|
              state.instance_variable_set(:"@#{name}", value)
            end
          end

          def load_counters(vic)
            load_display_state(vic)
            vic.instance_variable_get(:@character_buffer).replace(@character_buffer)
            vic.instance_variable_get(:@color_buffer).replace(@color_buffer)
            { raster_match: @raster_match, lp_low: @lp_low, lp_triggered: @lp_triggered,
              fetch_d011: @fetch_d011 }.each { |name, value| vic.instance_variable_set(:"@#{name}", value) }
            sequencer = vic.instance_variable_get(:@sequencer)
            %i[@vertical_border @vertical_armed @main_border].zip(@borders).each do |flop, value|
              sequencer.instance_variable_set(flop, value)
            end
          end

          def load_sprites(vic)
            sprites = vic.instance_variable_get(:@sprites)
            sprites.instance_variable_set(:@any_dma, @dma_bits.positive?)
            @sprites.each_with_index do |counters, n|
              sprite = sprites[n]
              counters.each { |name, value| sprite.instance_variable_set(:"@#{name}", value) }
              sprite.instance_variable_set(:@dma, @dma_bits.anybits?(1 << n))
              sprite.instance_variable_set(:@display_on, @display_bits.anybits?(1 << n))
            end
          end
        end
      end
    end
  end
end
