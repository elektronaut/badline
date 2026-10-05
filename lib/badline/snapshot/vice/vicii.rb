# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      # VIC-II 1.3 as x64sc writes it, and VIC-IISC 1.4, the same fields
      # under a new name, as VICE's development versions write it: the model, the registers, the beam's
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
        TRUNK_NAME = "VIC-IISC"
        MAJOR = 1
        MINOR = 3
        VERSIONS = ["VIC-II 1.3", "VIC-IISC 1.4"].freeze
        # The VIC model and region each of VICE's model numbers builds: the
        # 6569, the 8565 and the 6569R1 on PAL, the 6567 and the 8562 on
        # NTSC, the 6567R56A on old NTSC and the 6572 on PAL-N.
        VIC_MODELS = %i[mos6569 mos8565 mos6569 mos6569 mos8565 mos6569 mos6569].freeze
        REGIONS = [Region::PAL, Region::PAL, Region::PAL, Region::NTSC, Region::NTSC, Region::NTSC_OLD,
                   Region::DREAN].freeze
        FRAME_WIDTH = 384
        # The pixel pipeline x64sc keeps between cycles, in bytes.
        PIPELINE = 16 + 32 + 6 + 32 + 8 + 3 + 24 + 0x2f + 2 + 4

        module_function

        def export(computer)
          vic = computer.vic
          fields = FieldWriter.new.byte(number(vic)).bytes(vic.register_file)
          beam(vic, fields)
          counters(vic, fields)
          borders(vic, fields)
          fields.bytes(Array.new(0x400) { |offset| computer.address_bus.color_ram.nibble(0xd800 + offset) })
          8.times { |n| sprite(vic, n, fields) }
          pipeline(vic, fields)
          height = frame_height(vic.region)
          fields.dword(drawn_line(vic)).dword(FRAME_WIDTH).dword(height).dword(FRAME_WIDTH)
          fields.zeros(FRAME_WIDTH * (height + 4))
          fields.section(NAME, MAJOR, MINOR)
        end

        # VICE has no HMOS chip for old NTSC or PAL-N, so an 8565 there is
        # written as the NMOS one.
        def number(vic)
          hmos = vic.model == :mos8565
          case vic.region.name
          when :ntsc then hmos ? 4 : 3
          when :ntscold then 5
          when :drean then 6
          else hmos ? 1 : 0
          end
        end

        # x64sc's frame buffer, in lines, which it reads back at the height
        # the module gives: 312 on PAL and PAL-N, 275 on either NTSC.
        def frame_height(region) = region.lines_per_frame == 312 ? 312 : 275

        # VICE's cycle in the line is badline's column plus one, so
        # badline's last column is VICE's cycle 0 of the next line. VICE
        # moves its line on in cycle 0, but line 0 a cycle later, holding
        # the last line's number in cycle 0 with the start of frame flag
        # set.
        def last_column?(vic) = vic.column + 1 == vic.region.cycles_per_line

        def vice_cycle(vic) = last_column?(vic) ? 0 : vic.column + 1

        def frame_start?(vic) = last_column?(vic) && vic.rasterline + 1 == vic.region.lines_per_frame

        def vice_line(vic)
          line = vic.rasterline
          last_column?(vic) && !frame_start?(vic) ? line + 1 : line
        end

        # The line VICE's frame buffer is drawing, its line but for the
        # last, where it starts the next frame.
        def drawn_line(vic)
          line = vice_line(vic)
          line >= vic.region.lines_per_frame - 1 ? 0 : line
        end

        def beam(vic, fields)
          registers = vic.registers
          fields.dword(vice_cycle(vic)).dword(0).dword(vice_line(vic)).flag(frame_start?(vic))
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

        # The module a snapshot has, under either name.
        def find(container) = container[NAME] || container[TRUNK_NAME]

        def reads?(section) = VERSIONS.include?(section.to_s)

        # VICE's model number, which a snapshot of a model badline doesn't
        # build fails on.
        def model_number(section)
          number = FieldReader.new(section).byte
          return number if number < VIC_MODELS.length

          raise FormatError, "#{section}: VICE's VIC-II model #{number}, which badline doesn't build"
        end

        def model(section) = VIC_MODELS[model_number(section)]

        def region(section) = REGIONS[model_number(section)]

        def import(section, computer)
          snapshot = Import.new(FieldReader.new(section))
          snapshot.apply(computer)
        end
      end
    end
  end
end
