# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # VIC-II 1.3 as x64sc writes it: the model, the registers, the beam's
      # line and cycle, the IRQ latch, the video counters and buffers, the
      # light pen, the borders, colour RAM and each sprite's counters, then
      # x64sc's pixel pipeline and its frame buffer.
      #
      # Written: what badline's VIC holds in VICE's terms. The pixel
      # pipeline and frame buffer are left blank, as VICE repaints on
      # loading.
      #
      # Read: the registers, colour RAM, the IRQ latch and collisions, the
      # video counters and buffers and the sprite counters. The VIC is put
      # at the start of the snapshot's line and clocked on its own to the
      # snapshot's cycle, so its fetch and sprite state match the line, then
      # takes the snapshot's counters. Its pixel pipeline starts empty, so
      # the first pixels drawn may differ.
      module VICII
        NAME = "VIC-II"
        MAJOR = 1
        MINOR = 3
        MODELS = %i[mos6569 mos8565].freeze
        FRAME_WIDTH = 384
        FRAME_HEIGHT = 312
        # The pixel pipeline x64sc keeps between cycles, in bytes.
        PIPELINE = 16 + 32 + 6 + 32 + 8 + 3 + 24 + 0x2f + 2 + 4

        module_function

        def export(computer)
          vic = computer.vic
          fields = FieldWriter.new.byte(MODELS.index(vic.model) || 0).bytes(vic.register_file)
          beam(vic, fields)
          counters(vic, fields)
          borders(vic, fields)
          fields.bytes(Array.new(0x400) { |offset| computer.address_bus.color_ram.nibble(0xd800 + offset) })
          8.times { |n| sprite(vic, n, fields) }
          pipeline(vic, fields)
          fields.dword(vic.rasterline).dword(FRAME_WIDTH).dword(FRAME_HEIGHT).dword(FRAME_WIDTH)
          fields.zeros(FRAME_WIDTH * (FRAME_HEIGHT + 4))
          fields.section(NAME, MAJOR, MINOR)
        end

        def beam(vic, fields)
          registers = registers(vic)
          fields.dword(vic.column).dword(0).dword(vic.rasterline).byte(0)
          fields.byte((registers[0x19] & 0x0f) | (vic.interrupted? ? 0x80 : 0))
          fields.dword(registers.raster_target).flag(vic.instance_variable_get(:@raster_match))
          %i[@character_buffer @color_buffer].each do |buffer|
            fields.bytes(vic.instance_variable_get(buffer).map { |value| value || 0 })
          end
          fields.byte(0).dword(0).zeros(65 * 8) # x64sc's graphics buffer and draw buffer
        end

        def counters(vic, fields)
          registers = registers(vic)
          state = display_state(vic)
          fields.dword(registers.yscroll).flag(state.instance_variable_get(:@bad_lines_enabled))
          fields.byte(registers[0x1e]).byte(registers[0x1f]).byte(0)
          fields.dword(state.display? ? 0 : 1)
          [state.vc_base, state.vc, state.rc, state.vmli].each { |counter| fields.dword(counter) }
          fields.dword(state.bad_line_condition? ? 1 : 0)
          fields.flag(vic.instance_variable_get(:@lp_low)).flag(vic.instance_variable_get(:@lp_triggered))
          fields.dword(registers[0x13]).dword(registers[0x14]).dword(0).qword(0)
          fields.byte(vic.instance_variable_get(:@fetch_d011)).dword(0)
          fields.dword(sprite_bits(vic, :@display_on)).byte(sprite_bits(vic, :@dma))
        end

        def borders(vic, fields)
          sequencer = vic.instance_variable_get(:@sequencer)
          fields.byte(0xff).byte(0).byte(0).byte(0) # last colour register and value, last bus bytes
          %i[@vertical_border @vertical_armed @main_border].each do |flop|
            fields.flag(sequencer.instance_variable_get(flop))
          end
          fields.byte(0xff - (5 * vic.rasterline))
        end

        def sprite(vic, index, fields)
          sprite = sprites(vic)[index]
          fields.dword(sprite.instance_variable_get(:@sr))
          fields.byte(sprite.instance_variable_get(:@mc)).byte(sprite.instance_variable_get(:@mcbase)).byte(0)
          fields.flag(sprite.instance_variable_get(:@exp_ff)).dword(sprite.x)
        end

        # Blank but for the colour registers and the sprite priority,
        # multicolour and expansion bits, which x64sc keeps copies of.
        def pipeline(vic, fields)
          file = vic.register_file
          fields.zeros(16 + 32).bytes([file[0x1b], file[0x1c], file[0x1d], 0, 0, 0])
          fields.zeros(32 + 8 + 3 + 24).bytes(file.first(0x2f)).byte(0xff).byte(0).dword(0)
        end

        def sprite_bits(vic, flag)
          8.times.sum { |n| sprites(vic)[n].instance_variable_get(flag) ? 1 << n : 0 }
        end

        def registers(vic) = vic.instance_variable_get(:@registers)
        def display_state(vic) = vic.instance_variable_get(:@display_state)
        def sprites(vic) = vic.instance_variable_get(:@sprites)

        def model(section) = MODELS.fetch(FieldReader.new(section).byte, :mos6569)

        def import(section, computer)
          snapshot = Import.new(FieldReader.new(section))
          snapshot.apply(computer)
        end
      end
    end
  end
end
