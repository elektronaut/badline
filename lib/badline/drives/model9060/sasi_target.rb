# frozen_string_literal: true

require "badline/drives/model9060/sasi_commands"

module Badline
  module Drives
    class Model9060
      # The D9060's and D9090's hard disk controller (Tandon 188008) as the
      # DOS board's SASI host sees it, at the level of the bus's lines.
      #
      # The host selects it by raising SEL with bit 0 on the data bus, and
      # it answers with BSY. It then runs one command through the bus's
      # phases, which C/D, I/O and MSG name: six command bytes from the
      # host, the data in or out, a status byte and a message byte, after
      # which it lets go of BSY. Each byte waits on REQ, which the host
      # answers with ACK, and REQ rises again a cycle later for the next.
      #
      # The controller's work between the phases (a seek, the turn to the
      # block, the block under the head) delays the next REQ. `clock`
      # counts that time out, one cycle of the DOS board's 1 MHz at a time,
      # and `quiet?` says when there is none left to count. SASICommands
      # runs the commands against the disk, a Storage::D90Image, or nil
      # with none inserted.
      class SASITarget
        include SASICommands

        BUS_FREE = 0
        COMMAND = 1
        DATA_IN = 2
        DATA_OUT = 3
        STATUS = 4
        MESSAGE = 5

        COMMAND_LENGTH = 6

        attr_accessor :disk
        attr_reader :phase

        def initialize(disk = nil)
          @disk = disk
          @cycle = 0
          @cylinder = 0
          reset_geometry
          reset
        end

        # RST: the controller drops whatever it was doing and frees the bus.
        def reset
          @phase = BUS_FREE
          @request = false
          @delay = 0
          @command = []
          @buffer = []
          @index = 0
          @writing = false
          @sense = [0, 0, 0, 0]
          @last_sense = @sense
          @fast = false
        end

        def busy? = @phase != BUS_FREE

        def request? = @request

        # C/D: a command, status or message byte rather than data.
        def control? = [COMMAND, STATUS, MESSAGE].include?(@phase)

        # I/O: a byte from the controller to the host.
        def input? = [DATA_IN, STATUS, MESSAGE].include?(@phase)

        def message? = @phase == MESSAGE

        def quiet? = @delay.zero?

        # The byte the controller puts on the data bus, while I/O is set.
        def data = input? ? @buffer[@index] || 0 : 0

        # SEL with the host's data bus. The controller answers to bit 0
        # while the bus is free.
        def select(bus)
          return if busy? || bus.nobits?(0x01)

          enter(COMMAND, Array.new(COMMAND_LENGTH, 0), 1)
        end

        # ACK for the byte REQ asked for. The host's data bus carries a
        # byte to the controller in the command and data out phases, and
        # is ignored in the others.
        def acknowledge(bus)
          return unless @request

          @request = false
          @buffer[@index] = bus if @phase == COMMAND || @phase == DATA_OUT
          @index += 1
          @index < @buffer.length ? @delay = 1 : finish_phase
        end

        def clock
          @cycle += 1
          return if @delay.zero?

          @delay -= 1
          arrive if @delay.zero?
        end

        private

        def enter(phase, bytes, delay)
          @phase = phase
          @buffer = bytes
          @index = 0
          @request = false
          @delay = [delay, 1].max
        end

        def arrive
          if @writing
            @writing = false
            store_buffer
          else
            @request = true
          end
        end

        def finish_phase
          case @phase
          when COMMAND then start(@buffer.dup)
          when DATA_IN then report
          when DATA_OUT then data_received
          when STATUS then enter(MESSAGE, [@sense[0]], 1)
          else @phase = BUS_FREE
          end
        end

        def start(command)
          @command = command
          @last_sense = @sense
          @sense = [0, 0, 0, 0]
          execute
        end

        # The status byte: 0 for a command that went well, $02 (check
        # condition) for one that failed, whose error Request Sense reads.
        def report(delay = 1)
          enter(STATUS, [@sense[0].positive? ? 0x02 : 0x00], delay)
        end

        def refuse(error)
          @sense = [error, (@command[1] & 0xe0) | ((lba >> 16) & 0x1f), (lba >> 8) & 0xff, lba & 0xff]
          report
        end
      end
    end
  end
end
