# frozen_string_literal: true

module Badline
  module KernalTrap
    # The +keep+ of an IEEELineStep that only reads its register.
    IEEE_LINE_READ = -1

    # One step a KERNAL takes on the IEEE-488 bus's lines: a write of +set+
    # to the register at +address+, or with a +keep+ mask the register read
    # first, its +keep+ bits kept and +set+ ORed in, or with keep
    # IEEE_LINE_READ only a read. Returns the value written, or read.
    IEEELineStep = Data.define(:address, :keep, :set) do
      def act_on(bus)
        return bus.peek(address) if keep == IEEE_LINE_READ

        value = keep.zero? ? set : (bus.peek(address) & keep) | set
        bus.poke(address, value)
        value
      end
    end

    # The steps a KERNAL takes on the bus's lines at each moment the traps
    # stand in for, each run in order (#run_steps), the last one's value
    # returned: +timer+ starts the timer that times out each byte's
    # handshake, +attention+ readies the bus and pulls ATN low for TALK
    # and LISTEN, +byte_sent+ ends a byte sent, +release_attention+ ends
    # SECOND, TKSA, UNTALK and UNLISTEN by letting ATN go, +listen_to_talker+
    # ends TKSA and ACPTR with the computer listening, and +release+ ends
    # UNTALK and UNLISTEN.
    IEEELines = Data.define(:timer, :attention, :byte_sent, :release_attention, :listen_to_talker, :release) do
      def run_steps(steps, bus)
        value = 0
        steps.each { |step| value = step.act_on(bus) }
        value
      end
    end

    # Where a KERNAL keeps the eight IEEE-488 bus primitives, which are
    # internal routines, not jump table entries, the ZeroPage of its file
    # variables, and the steps it takes on the bus's lines (IEEELines).
    # Each ROM set has its own.
    #
    # On a PET, TALK and LISTEN take no device number in A: they send $40
    # or $20 ORed with FA. UNTALK and UNLISTEN send $5F and $3F through the
    # same code, and SECOND, TKSA, UNTALK and UNLISTEN end by letting go of
    # ATN themselves. LOAD and SAVE run in the ROM, through the primitives.
    # +overwrites_device+ says UNTALK and UNLISTEN store their command in
    # FA before they send it.
    IEEELayout = Data.define(:talk, :listen, :second, :tksa, :ciout, :untalk, :unlisten, :acptr, :overwrites_device,
                             :zero_page, :lines) do
      # The KERNAL is mapped unless something lies over it.
      def kernal_mapped?(bus) = bus.kernal_mapped?

      # Starts the timer that times out the handshake of each byte.
      def time_serial_byte(bus, _timer_high)
        lines.run_steps(lines.timer, bus)
      end

      # TALK and LISTEN: the handshake lines let go, then ATN pulled low.
      def attention(bus)
        lines.run_steps(lines.attention, bus)
      end

      # The end of a byte sent: DAV and the data lines let go.
      def byte_sent(bus)
        lines.run_steps(lines.byte_sent, bus)
      end

      # The end of SECOND, TKSA, UNTALK and UNLISTEN: ATN let go. Returns
      # the value written, which the ROM leaves in A.
      def release_attention(bus)
        lines.run_steps(lines.release_attention, bus)
      end

      # TKSA and ACPTR end listening: NRFD and NDAC pulled low.
      def listen_to_talker(bus)
        lines.run_steps(lines.listen_to_talker, bus)
      end

      # The end of UNTALK and UNLISTEN, which address the bus as TALK and
      # LISTEN do, send their command and let ATN go. Returns the value
      # the ROM leaves in A.
      def release_serial_lines(bus)
        lines.run_steps(lines.release, bus)
      end
    end

    # A PET drives the bus's control lines from three chips: ATN from VIA
    # PB2 and NRFD from PB1 at $E840, NDAC from PIA 2's CA2 and DAV from its
    # CB2, through the control registers at $E821 and $E823, which the ROM
    # writes $34 to pull a line low and $3C to let it go, and the data lines
    # from PIA 2's port B at $E822. Each handshake times out on VIA timer 1,
    # which the ROM starts with a write of $FF to $E845. The steps leave the
    # lines as each primitive leaves them.
    PET_ATTENTION = [
      IEEELineStep.new(address: 0xe840, keep: 0xff, set: 0x02),
      IEEELineStep.new(address: 0xe821, keep: 0, set: 0x3c),
      IEEELineStep.new(address: 0xe840, keep: 0xfb, set: 0)
    ].freeze
    PET_BYTE_SENT = [
      IEEELineStep.new(address: 0xe823, keep: 0, set: 0x3c),
      IEEELineStep.new(address: 0xe822, keep: 0, set: 0xff)
    ].freeze
    PET_RELEASE_ATTENTION = [IEEELineStep.new(address: 0xe840, keep: 0xff, set: 0x04)].freeze
    PET_LINES = IEEELines.new(
      timer: [IEEELineStep.new(address: 0xe845, keep: 0, set: 0xff)].freeze,
      attention: PET_ATTENTION, byte_sent: PET_BYTE_SENT, release_attention: PET_RELEASE_ATTENTION,
      listen_to_talker: [IEEELineStep.new(address: 0xe840, keep: 0xfd, set: 0),
                         IEEELineStep.new(address: 0xe821, keep: 0, set: 0x34)].freeze,
      release: (PET_ATTENTION + PET_BYTE_SENT + PET_RELEASE_ATTENTION).freeze
    )

    # The file variables of the BASIC 2 and BASIC 4 KERNALs, which keep
    # them at the same addresses. SAVE copies STAL at $FB to SAL at $C7 and
    # walks SAL up to EAL at $C9. LOAD keeps no MEMUSS: it stores each byte
    # at STAL, which starts at the file's own address, and ends with EAL
    # set from it, so +load_address+ names STAL.
    PET_ZERO_PAGE = ZeroPage.new(
      status: 0x96, verify: 0x9d, start_address: 0xc7, end_address: 0xc9, filename_length: 0xd1,
      secondary_address: 0xd3, device: 0xd4, filename_address: 0xda, save_start: 0xfb, load_address: 0xfb
    )

    # BASIC 1's, some of them outside the zero page: ST at $020C and VERCK
    # at $020B. SAVE copies STAL at $F7 to SAL at $E3 and walks SAL up to
    # EAL at $E5. LOAD from the IEEE bus stores each byte at STAL, which it
    # sets to $0400 itself.
    PET_BASIC1_ZERO_PAGE = ZeroPage.new(
      status: 0x020c, verify: 0x020b, start_address: 0xe3, end_address: 0xe5, filename_length: 0xee,
      secondary_address: 0xf0, device: 0xf1, filename_address: 0xf9, save_start: 0xf7, load_address: 0xf7
    )

    # BASIC 1, 901447-06 and 901447-07. Its UNTALK and UNLISTEN store $5F
    # and $3F in FA at $F1 before they send it. LOAD and SAVE send TALK and
    # LISTEN without a secondary address.
    PET_BASIC1_LAYOUT = IEEELayout.new(
      talk: 0xf0b6, listen: 0xf0ba, second: 0xf12c, tksa: 0xf15b,
      ciout: 0xf167, untalk: 0xf17a, unlisten: 0xf17e, acptr: 0xf187, overwrites_device: true,
      zero_page: PET_BASIC1_ZERO_PAGE, lines: PET_LINES
    )

    # BASIC 2, 901465-03. Its LOAD sends the secondary address after TALK
    # with SECOND, not TKSA.
    PET_BASIC2_LAYOUT = IEEELayout.new(
      talk: 0xf0b6, listen: 0xf0ba, second: 0xf128, tksa: 0xf164,
      ciout: 0xf16f, untalk: 0xf17f, unlisten: 0xf183, acptr: 0xf18c, overwrites_device: false,
      zero_page: PET_ZERO_PAGE, lines: PET_LINES
    )

    # BASIC 4, 901465-22. LISTEN at $F0D5 is the operand of the BIT
    # instruction that skips it on the way from TALK.
    PET_BASIC4_LAYOUT = IEEELayout.new(
      talk: 0xf0d2, listen: 0xf0d5, second: 0xf143, tksa: 0xf193,
      ciout: 0xf19e, untalk: 0xf1ae, unlisten: 0xf1b9, acptr: 0xf1c0, overwrites_device: false,
      zero_page: PET_ZERO_PAGE, lines: PET_LINES
    )
  end
end
