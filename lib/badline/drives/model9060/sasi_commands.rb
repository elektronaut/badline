# frozen_string_literal: true

module Badline
  module Drives
    class Model9060
      # The commands the DOS board's SASI ROM (300515) sends, against the
      # disk's blocks. A command's second to fourth bytes hold the drive
      # (bits 5-7) and the block's LBA, its fifth the blocks to move.
      #
      # | Op | Command | Data |
      # | --- | --- | --- |
      # | $00 | Test Unit Ready | |
      # | $01 | Recalibrate: seek to cylinder 0 | |
      # | $03 | Request Sense: the last command's error and its LBA | 4 in |
      # | $04 | Format Unit | |
      # | $08 | Read | 256 a block in |
      # | $0A | Write | 256 a block out |
      # | $0B | Seek | |
      # | $0C | Vendor: read the controller's block buffer (unverified) | 256 in |
      # | $0E | Vendor: write the controller's block buffer (unverified) | 256 out |
      # | $E3 | Vendor: four bytes, all zero here (unverified) | 4 in |
      # | $C0 | Vendor: set the geometry (unverified) | |
      #
      # $C0's fifth and sixth bytes are taken as the last head and the last
      # sector of a head, as the ROM sends them (5 and 31 on a D9090 at
      # boot). Its other bytes aren't used.
      #
      # An error's sense byte has its class in bits 4-5 and its code in bits
      # 0-3, with bit 7 set when the LBA after it names the block. The ROM
      # reads that byte from the message phase after a check condition,
      # and the controller sends it there.
      #
      # Format Unit erases the disk at once and puts the controller in a
      # fast mode, where Read, Write and Seek take no seek or rotation time,
      # for the DOS's passes over the whole disk. Any other command ends
      # it. Outside it a seek takes 3 ms a cylinder and 15 ms to settle, and
      # the disk turns 32 blocks in 16.7 ms.
      module SASICommands
        DRIVE_NOT_READY = 0x04
        WRITE_FAULT = 0x03
        INVALID_COMMAND = 0x20
        ILLEGAL_ADDRESS = 0xa1

        BLOCK = 256
        SECTOR_CYCLES = 521
        STEP_CYCLES = 3_000
        SETTLE_CYCLES = 15_000

        DISK_COMMANDS = [0x00, 0x01, 0x04, 0x08, 0x0a, 0x0b].freeze
        FAST_COMMANDS = [0x08, 0x0a, 0x0b].freeze

        attr_reader :heads, :sectors, :cylinder

        def fast? = @fast

        private

        def reset_geometry
          @heads = 4
          @sectors = 32
          @block_buffer = Array.new(BLOCK, 0)
        end

        def execute
          @fast = false unless FAST_COMMANDS.include?(@command[0])
          case @command[0]
          when 0x03 then enter(SASITarget::DATA_IN, @last_sense.dup, 1)
          when 0x0c then enter(SASITarget::DATA_IN, @block_buffer.dup, 1)
          when 0x0e then enter(SASITarget::DATA_OUT, Array.new(BLOCK, 0), 1)
          when 0xe3 then enter(SASITarget::DATA_IN, [0, 0, 0, 0], 1)
          when 0xc0 then set_geometry
          else disk_command
          end
        end

        def disk_command
          return refuse(INVALID_COMMAND) unless DISK_COMMANDS.include?(@command[0])
          return refuse(DRIVE_NOT_READY) unless @disk && (@command[1] >> 5).zero?

          case @command[0]
          when 0x00 then report
          when 0x01 then report(travel(0))
          when 0x04 then format_unit
          else block_command
          end
        end

        def block_command
          return refuse(ILLEGAL_ADDRESS) unless @disk.blocks?(lba, @command[0] == 0x0b ? 1 : count)

          case @command[0]
          when 0x08 then read
          when 0x0a then enter(SASITarget::DATA_OUT, Array.new(count * BLOCK, 0), 1)
          else report(travel(cylinder_of(lba)))
          end
        end

        def lba = ((@command[1] & 0x1f) << 16) | (@command[2] << 8) | @command[3]

        def count = @command[4].zero? ? 256 : @command[4]

        def cylinder_of(block) = block / (@heads * @sectors)

        def set_geometry
          @heads = @command[4] + 1
          @sectors = @command[5] + 1
          report
        end

        def read
          bytes = @disk.read_blocks(lba, count)
          @block_buffer = bytes.last(BLOCK)
          enter(SASITarget::DATA_IN, bytes, access_cycles)
        end

        def data_received
          if @command[0] == 0x0e
            @block_buffer = @buffer.dup
            report
          else
            @writing = true
            @delay = access_cycles
          end
        end

        def store_buffer
          @disk.write_blocks(lba, @buffer)
          @block_buffer = @buffer.last(BLOCK)
          report
        rescue Storage::WriteError
          refuse(WRITE_FAULT)
        end

        def format_unit
          blocks = @heads * @sectors
          (0...@disk.block_count).step(blocks) do |first|
            @disk.write_blocks(first, Array.new([blocks, @disk.block_count - first].min * BLOCK, 0))
          end
          @fast = true
          report
        rescue Storage::WriteError
          refuse(WRITE_FAULT)
        end

        # The seek to the block's cylinder, the turn until the block comes
        # under the head, and the blocks passing under it.
        def access_cycles
          return 1 if @fast

          seek = travel(cylinder_of(lba))
          slot = ((@cycle + seek) / SECTOR_CYCLES) % @sectors
          seek + ((((lba % @sectors) - slot) % @sectors) * SECTOR_CYCLES) + (count * SECTOR_CYCLES)
        end

        def travel(target)
          steps = (target - @cylinder).abs
          @cylinder = target
          return 1 if @fast || steps.zero?

          (steps * STEP_CYCLES) + SETTLE_CYCLES
        end
      end
    end
  end
end
