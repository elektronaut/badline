# frozen_string_literal: true

module Badline
  module KernalTrap
    # Where a machine's KERNAL keeps the routines the traps stand in for,
    # and the ROM code they hand over to, with the steps that depend on the
    # machine around it: whether the KERNAL is mapped in, and the release of
    # the serial lines.
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
    Layout = Data.define(:load, :save, :searching_message, :loading_message, :load_byte_loop, :load_done,
                         :file_not_found_exit, :missing_file_name_exit, :saving_message, :clock_release,
                         :data_release, :save_done, :talk, :listen, :second, :tksa, :ciout, :untalk,
                         :unlisten, :acptr) do
      # Whether the CPU reads the KERNAL ROM at the trapped addresses: the
      # 6510 port's banking bits select it.
      def kernal_mapped?(bus)
        bus.io_port.kernal?
      end

      # The ROM's release of the serial bus ($EE03): ATN ($EDBE), then the
      # clock ($EE85), then the data line ($EE97), each a read of CIA 2's
      # port A, a mask and a write back, so the input bits written back
      # follow the lines as each one is let go. Returns the last value
      # written, which the ROM leaves in A.
      def release_serial_lines(bus)
        value = 0
        [0xf7, 0xef, 0xdf].each do |mask|
          value = bus.peek(0xdd00) & mask
          bus.poke(0xdd00, value)
        end
        value
      end
    end

    # The C64 KERNAL, revision 3. The SX-64's, 251104-04, differs from it
    # only in bytes none of these addresses reach.
    C64_LAYOUT = Layout.new(
      load: 0xf4a5, save: 0xf5ed,
      searching_message: 0xf5af, loading_message: 0xf5d2, load_byte_loop: 0xf4f3, load_done: 0xf5a9,
      file_not_found_exit: 0xf704, missing_file_name_exit: 0xf710,
      saving_message: 0xf68f, clock_release: 0xee85, data_release: 0xee97, save_done: 0xf657,
      talk: 0xed09, listen: 0xed0c, second: 0xedb9, tksa: 0xedc7,
      ciout: 0xeddd, untalk: 0xedef, unlisten: 0xedfe, acptr: 0xee13
    )
  end
end
