# frozen_string_literal: true

module Badline
  module KernalTrap
    # Where a machine's KERNAL keeps the routines the traps stand in for,
    # and the ROM code they hand over to, with the steps that depend on the
    # machine around it: whether the KERNAL is mapped in, the timer that
    # times each serial byte and the release of the serial lines.
    #
    # +load+ and +save+ are the default ILOAD and ISAVE vector targets.
    # LOAD hands over to the SEARCHING FOR and LOADING/VERIFYING messages,
    # the byte loop that retries a timed-out byte until RUN/STOP, the
    # successful return (CLC, LDX $AE, LDY $AF, RTS) and the FILE NOT FOUND
    # and MISSING FILE NAME error exits. SAVE hands over to the SAVING
    # message, the two line releases that end UNLISTEN (clock, then data,
    # leaving A as read from the port), the successful return (CLC, RTS)
    # and the MISSING FILE NAME exit. The rest are the serial bus
    # primitives' entry points.
    #
    # +banked+ says whether the 6510 port can bank the KERNAL out, and so
    # whether RAM lies under every ROM and the I/O. +mmu+ says the C128's
    # MMU maps the KERNAL instead, and that the file name and the file's
    # bytes lie in the banks the KERNAL keeps at FNBANK and BA. Each
    # serial byte starts a one-shot timer by writing the high byte of its
    # count to +serial_timer+, and the control value TIMER_ONE_SHOT_START
    # to +serial_timer_start+ where the timer has a control register to
    # start it (a CIA's), or nil where the write to the high byte starts it
    # (a VIA's timer 2). A KERNAL that times its bytes with a loop has no
    # +serial_timer+. The ROM lets go of each serial line by reading a
    # port, masking the line's bit off and writing it back: ATN at
    # +atn_port+ with +atn_mask+, then the clock and the data line.
    Layout = Data.define(:load, :save, :searching_message, :loading_message, :load_byte_loop, :load_done,
                         :file_not_found_exit, :missing_file_name_exit, :saving_message, :clock_release,
                         :data_release, :save_done, :talk, :listen, :second, :tksa, :ciout, :untalk,
                         :unlisten, :acptr, :banked, :serial_timer, :serial_timer_start, :atn_port, :atn_mask,
                         :clock_port, :clock_mask, :data_port, :data_mask, :mmu) do
      # Whether the CPU reads the KERNAL ROM at the trapped addresses: on a
      # banked machine, the 6510 port's banking bits select it, and on the
      # C128 the MMU.
      def kernal_mapped?(bus)
        return bus.system_rom_mapped? if mmu

        !banked || bus.io_port.kernal?
      end

      # Stores a loaded file's bytes from +address+ on: on a banked machine
      # into the RAM under whatever is banked in, on the C128 into the RAM
      # of the bank at BA, and otherwise where the ROM's byte loop would
      # store them, through the bus.
      def store_file(bus, address, bytes)
        return bus.write_bank(bus.peek(BANK), address, bytes) if mmu
        return bus.ram.write(address, bytes) if banked

        bytes.each_with_index { |byte, i| bus.poke(address + i, byte) }
      end

      # The file name's byte at +address+, in the bank at FNBANK on the
      # C128.
      def filename_byte(bus, address)
        mmu ? bus.peek_bank(bus.peek(FILENAME_BANK), address) : bus.peek(address)
      end

      # The byte at +address+ a SAVE writes or a VERIFY compares, in the bank
      # at BA on the C128.
      def file_byte(bus, address)
        mmu ? bus.peek_bank(bus.peek(BANK), address) : bus.peek(address)
      end

      # Starts the timer the ROM times a serial byte with, its count's high
      # byte +timer_high+.
      def time_serial_byte(bus, timer_high)
        return unless serial_timer

        bus.poke(serial_timer, timer_high)
        start = serial_timer_start
        bus.poke(start, TIMER_ONE_SHOT_START) if start
      end

      # The ROM's release of the serial bus: ATN, then the clock, then the
      # data line, each a read of its port, a mask and a write back, so the
      # input bits written back follow the lines as each one is let go.
      # Returns the last value written, which the ROM leaves in A.
      def release_serial_lines(bus)
        release_line(bus, atn_port, atn_mask)
        release_line(bus, clock_port, clock_mask)
        release_line(bus, data_port, data_mask)
      end

      private

      def release_line(bus, port, mask)
        value = bus.peek(port) & mask
        bus.poke(port, value)
        value
      end
    end

    # A CIA's control value that starts its timer: force load, one-shot,
    # start.
    TIMER_ONE_SHOT_START = 0x19

    # Where the C128 KERNAL keeps the bank a LOAD or SAVE goes to (BA) and
    # the bank of the file name (FNBANK).
    BANK = 0xc6
    FILENAME_BANK = 0xc7

    # The C64 KERNAL, revision 3. The SX-64's, 251104-04, differs from it
    # only in bytes none of these addresses reach. It times serial bytes
    # with CIA 1's timer B, and drives the lines from CIA 2's port A
    # ($EE03: ATN $EDBE, clock $EE85, data $EE97).
    C64_LAYOUT = Layout.new(
      load: 0xf4a5, save: 0xf5ed,
      searching_message: 0xf5af, loading_message: 0xf5d2, load_byte_loop: 0xf4f3, load_done: 0xf5a9,
      file_not_found_exit: 0xf704, missing_file_name_exit: 0xf710,
      saving_message: 0xf68f, clock_release: 0xee85, data_release: 0xee97, save_done: 0xf657,
      talk: 0xed09, listen: 0xed0c, second: 0xedb9, tksa: 0xedc7,
      ciout: 0xeddd, untalk: 0xedef, unlisten: 0xedfe, acptr: 0xee13,
      banked: true, serial_timer: 0xdc07, serial_timer_start: 0xdc0f,
      atn_port: 0xdd00, atn_mask: 0xf7, clock_port: 0xdd00, clock_mask: 0xef, data_port: 0xdd00, data_mask: 0xdf,
      mmu: false
    )

    # The VIC-20 KERNAL, 901486-07 (PAL). The NTSC one, 901486-06, differs
    # from it only at $E475, $EDE4-$EDE5, $FE3F, $FE44 and $FF5C-$FF70,
    # none of them here. Nothing banks it out. It times serial bytes with
    # VIA 2's timer 2 ($9129), drives ATN from VIA 1's PA7 ($911F) and the
    # clock and data lines from VIA 2's CA2 and CB2 ($912C), and UNLISTEN
    # lets them go at $EF09: ATN $EEC5, clock $EF84, data $E4A0.
    VIC20_LAYOUT = Layout.new(
      load: 0xf549, save: 0xf685,
      searching_message: 0xf647, loading_message: 0xf66a, load_byte_loop: 0xf58a, load_done: 0xf641,
      file_not_found_exit: 0xf787, missing_file_name_exit: 0xf793,
      saving_message: 0xf728, clock_release: 0xef84, data_release: 0xe4a0, save_done: 0xf6ef,
      talk: 0xee14, listen: 0xee17, second: 0xeec0, tksa: 0xeece,
      ciout: 0xeee4, untalk: 0xeef6, unlisten: 0xef04, acptr: 0xef19,
      banked: false, serial_timer: 0x9129, serial_timer_start: nil,
      atn_port: 0x911f, atn_mask: 0x7f, clock_port: 0x912c, clock_mask: 0xfd, data_port: 0x912c, data_mask: 0xdf,
      mmu: false
    )

    # The C128 KERNAL, 318020-05, in C128 mode: the jump table's targets
    # for the serial primitives, ILOAD's and ISAVE's default targets, and
    # the ROM's own tails. Its LOAD prints SEARCHING FOR at $F50F and
    # LOADING or VERIFYING at $F533, retries a byte at $F2CF and returns at
    # $F39B. FILE NOT FOUND leaves through $F685 and MISSING FILE NAME
    # through $F691. SAVE prints SAVING at $F5BC and returns at $F5B3, after
    # the UNLISTEN whose clock and data releases are $E545 and $E557. It
    # drives the lines from CIA 2's port A, and times serial bytes with
    # loops, not a timer.
    C128_LAYOUT = Layout.new(
      load: 0xf26c, save: 0xf54e,
      searching_message: 0xf50f, loading_message: 0xf533, load_byte_loop: 0xf2cf, load_done: 0xf39b,
      file_not_found_exit: 0xf685, missing_file_name_exit: 0xf691,
      saving_message: 0xf5bc, clock_release: 0xe545, data_release: 0xe557, save_done: 0xf5b3,
      talk: 0xe33b, listen: 0xe33e, second: 0xe4d2, tksa: 0xe4e0,
      ciout: 0xe503, untalk: 0xe515, unlisten: 0xe526, acptr: 0xe43e,
      banked: true, serial_timer: nil, serial_timer_start: nil,
      atn_port: 0xdd00, atn_mask: 0xf7, clock_port: 0xdd00, clock_mask: 0xef, data_port: 0xdd00, data_mask: 0xdf,
      mmu: true
    )
  end
end
