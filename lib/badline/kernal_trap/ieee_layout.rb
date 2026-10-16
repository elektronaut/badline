# frozen_string_literal: true

module Badline
  module KernalTrap
    # Where a PET KERNAL keeps the eight IEEE-488 bus primitives, which are
    # internal routines, not jump table entries, and the ZeroPage of its
    # file variables. Each ROM set has its own.
    #
    # TALK and LISTEN take no device number in A: they send $40 or $20
    # ORed with FA. UNTALK and UNLISTEN send $5F and $3F through the same
    # code, and SECOND, TKSA, UNTALK and UNLISTEN end by letting go of ATN
    # (VIA PB2) themselves. Each handshake times out on VIA timer 1, which
    # the ROM starts with a write of $FF to $E845. Nothing banks the KERNAL
    # out, and LOAD and SAVE run in the ROM, through the primitives.
    IEEELayout = Data.define(:talk, :listen, :second, :tksa, :ciout, :untalk, :unlisten, :acptr, :zero_page) do
      # The KERNAL is always mapped.
      def kernal_mapped?(_bus) = true
    end

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
      ciout: 0xf167, untalk: 0xf17a, unlisten: 0xf17e, acptr: 0xf187, zero_page: PET_BASIC1_ZERO_PAGE
    )

    # BASIC 2, 901465-03. Its LOAD sends the secondary address after TALK
    # with SECOND, not TKSA.
    PET_BASIC2_LAYOUT = IEEELayout.new(
      talk: 0xf0b6, listen: 0xf0ba, second: 0xf128, tksa: 0xf164,
      ciout: 0xf16f, untalk: 0xf17f, unlisten: 0xf183, acptr: 0xf18c, zero_page: PET_ZERO_PAGE
    )

    # BASIC 4, 901465-22. LISTEN at $F0D5 is the operand of the BIT
    # instruction that skips it on the way from TALK.
    PET_BASIC4_LAYOUT = IEEELayout.new(
      talk: 0xf0d2, listen: 0xf0d5, second: 0xf143, tksa: 0xf193,
      ciout: 0xf19e, untalk: 0xf1ae, unlisten: 0xf1b9, acptr: 0xf1c0, zero_page: PET_ZERO_PAGE
    )
  end
end
