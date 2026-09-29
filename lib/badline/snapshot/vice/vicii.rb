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
          registers = vic.registers
          fields.dword(vic.column).dword(0).dword(vic.rasterline).byte(0)
          fields.byte((registers[0x19] & 0x0f) | (vic.interrupted? ? 0x80 : 0))
          fields.dword(registers.raster_target).flag(vic.latch_bits.anybits?(1))
          [vic.character_buffer, vic.color_buffer].each { |buffer| fields.bytes(buffer.map { |value| value || 0 }) }
          fields.byte(0).dword(0).zeros(65 * 8) # x64sc's graphics buffer and draw buffer
        end

        def counters(vic, fields)
          registers = vic.registers
          state = vic.display_state
          fields.dword(registers.yscroll).flag(state.bad_lines_enabled)
          fields.byte(registers[0x1e]).byte(registers[0x1f]).byte(0)
          fields.dword(state.display? ? 0 : 1)
          [state.vc_base, state.vc, state.rc, state.vmli].each { |counter| fields.dword(counter) }
          fields.dword(state.bad_line_condition? ? 1 : 0)
          fields.flag(vic.latch_bits.anybits?(2)).flag(vic.latch_bits.anybits?(4))
          fields.dword(registers[0x13]).dword(registers[0x14]).dword(0).qword(0)
          fields.byte(vic.fetch_d011).dword(0)
          fields.dword(sprite_bits(vic, &:display_on)).byte(sprite_bits(vic, &:displaying?))
        end

        def borders(vic, fields)
          fields.byte(0xff).byte(0).byte(0).byte(0) # last colour register and value, last bus bytes
          vic.sequencer.borders.each { |flop| fields.flag(flop) }
          fields.byte(0xff - (5 * vic.rasterline))
        end

        def sprite(vic, index, fields)
          sprite = vic.sprites[index]
          fields.dword(sprite.sr).byte(sprite.mc).byte(sprite.mcbase).byte(0).flag(sprite.exp_ff).dword(sprite.x)
        end

        # Blank but for the colour registers and the sprite priority,
        # multicolour and expansion bits, which x64sc keeps copies of.
        def pipeline(vic, fields)
          file = vic.register_file
          fields.zeros(16 + 32).bytes([file[0x1b], file[0x1c], file[0x1d], 0, 0, 0])
          fields.zeros(32 + 8 + 3 + 24).bytes(file.first(0x2f)).byte(0xff).byte(0).dword(0)
        end

        def sprite_bits(vic)
          8.times.sum { |n| yield(vic.sprites[n]) ? 1 << n : 0 }
        end

        def reads?(section) = section.major == MAJOR && section.minor == MINOR

        # VICE's model numbers: the 6569, the 8565 and the 6569R1 run PAL;
        # the 6567, 8562 and 6567R56A NTSC, and the 6572 PAL-N, which badline
        # doesn't run yet.
        def model(section)
          number = FieldReader.new(section).byte
          return :mos8565 if number == 1
          return :mos6569 if [0, 2].include?(number)

          raise FormatError, "#{section}: an NTSC or PAL-N VIC-II (VICE model #{number}), which badline doesn't run"
        end

        def import(section, computer)
          snapshot = Import.new(FieldReader.new(section))
          snapshot.apply(computer)
        end
      end
    end
  end
end
