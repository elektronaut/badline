# frozen_string_literal: true

module Badline
  class PET
    class SuperPET < PET
      # The traps on the Waterloo 6809 ROM's IEEE-488 routines, which serve
      # device 8 from the virtual drive (KernalTrap::DOS) the 6502's traps
      # serve it from, after the ROM's source as Mike Naberezny hosts it
      # (opsys-all-clean-20101210-src.txt). Other devices fall through to
      # the ROM, which drives the bus.
      #
      # The routines take their argument in D and return with RTS: SetLstnr
      # and SetTalkr a file control block, whose byte 9 is the device, byte
      # 10 the secondary address and byte 0 the status, 3 after a timeout,
      # SetLstnr with the command's offset pushed before the call ($F0 to
      # open, $E0 to close, $60 for data), ByteOut_ the byte to send and
      # the byte-in routine none, returning the byte in D and setting bit 0
      # of the block's byte 12 at EOI. Each keeps the block's address at
      # $02 and the bus at $77-$7A: $20 listening or $40 talking, the
      # offset, the device and the secondary address. A language that hooks
      # a routine through its flag at $0580 gets the ROM's routine, which
      # calls the hook.
      #
      # The menu loads from "disk/1.", drive 1 of a dual drive. The virtual
      # drive has one, so a name on drive 1 opens the file on drive 0.
      class WaterlooTraps
        BYTE_OUT = 0xbe6f
        BYTE_IN = 0xbefb
        SET_LISTENER = 0xc072
        UNLISTEN = 0xc0d0
        SET_TALKER = 0xc0dd
        UNTALK = 0xc13c

        # The routines' user hook numbers, whose flags sit at $0580 on.
        HOOKS = { BYTE_OUT => 23, BYTE_IN => 24, SET_LISTENER => 27, UNLISTEN => 28, SET_TALKER => 29,
                  UNTALK => 30 }.freeze

        BLOCK = 0x02
        ACTIVE = 0x77
        LISTENING = 0x20
        TALKING = 0x40
        TIMED_OUT = 3

        OPEN = 0xf0
        CLOSE = 0xe0

        # The device the traps serve, or nil to serve none.
        attr_accessor :device

        def initialize(cpu:, bus:, dos:)
          @cpu = cpu
          @bus = bus
          @dos = dos
          @device = KernalTrap::Routine::DEVICE
          @listening = false
          @talking = false
          @channel = 0
          @frame = 0
          @buffer = []
        end

        def install
          HOOKS.each_key { |address| @cpu.install_trap(address) { call(address) } }
          self
        end

        def uninstall
          HOOKS.each_key { |address| @cpu.remove_trap(address) }
        end

        private

        def call(address)
          return unless @bus.peek(0x0580 + HOOKS.fetch(address)).zero?

          case address
          when SET_LISTENER then set_listener
          when BYTE_OUT then byte_out
          when UNLISTEN then unlisten
          when SET_TALKER then set_talker
          when BYTE_IN then byte_in
          else untalk
          end
        end

        def served?(block) = !@device.nil? && @bus.peek(block + 9) == @device

        def set_listener
          block = @cpu.d
          return unless served?(block)

          offset = @bus.peek(@cpu.s + 3)
          select(block, LISTENING, offset)
          @listening = true
          @frame = offset & 0xf0
          @buffer = []
          @dos.close(@channel) if @frame == CLOSE
          return_from_routine
        end

        def set_talker
          block = @cpu.d
          return unless served?(block)

          select(block, TALKING, 0x60)
          @talking = true
          return_from_routine
        end

        # Ends what the bus was doing, then addresses the block's device as
        # the routine does.
        def select(block, active, offset)
          finish_listening if @listening
          @talking = false
          @bus.poke(BLOCK, block >> 8)
          @bus.poke(BLOCK + 1, block & 0xff)
          @bus.poke(ACTIVE, active)
          @bus.poke(ACTIVE + 1, offset)
          @bus.poke(ACTIVE + 2, @bus.peek(block + 9))
          secondary = @bus.peek(block + 10)
          @bus.poke(ACTIVE + 3, secondary)
          @channel = secondary & 0x0f
        end

        def byte_out
          return unless @listening

          block = current_block
          if @bus.peek(block).zero?
            @buffer << (@cpu.d & 0xff)
            @bus.poke(block, TIMED_OUT) unless accepted?
          end
          @cpu.d = 0x00ff
          return_from_routine
        end

        def accepted? = [OPEN, CLOSE].include?(@frame) || @dos.listening?(@channel)

        def unlisten
          return unless @listening

          finish_listening
          @bus.poke(ACTIVE, 0)
          return_from_routine
        end

        def finish_listening
          @listening = false
          case @frame
          when OPEN then @dos.open(@channel, on_drive_zero(@buffer.pack("C*")))
          when CLOSE then nil
          else @dos.write(@channel, @buffer)
          end
          @buffer = []
        end

        def on_drive_zero(name) = name.start_with?("1:") ? "0:#{name[2..]}" : name

        def byte_in
          return unless @talking

          block = current_block
          byte = 0x0d
          if @bus.peek(block).zero?
            read, eoi = @dos.read(@channel)
            if read.nil?
              @bus.poke(block, TIMED_OUT)
            else
              byte = read
              @bus.poke(block + 12, @bus.peek(block + 12) | 0x01) if eoi
            end
          end
          @cpu.d = byte
          return_from_routine
        end

        def untalk
          return unless @talking

          @talking = false
          @bus.poke(ACTIVE, 0)
          return_from_routine
        end

        def current_block = (@bus.peek(BLOCK) << 8) | @bus.peek(BLOCK + 1)

        def return_from_routine
          s = @cpu.s
          @cpu.pc = (@bus.peek(s) << 8) | @bus.peek(s + 1)
          @cpu.s = (s + 2) & 0xffff
        end
      end
    end
  end
end
