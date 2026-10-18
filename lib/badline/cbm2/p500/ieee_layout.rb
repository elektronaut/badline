# frozen_string_literal: true

module Badline
  class CBM2
    class P500
      # Where the P500's KERNAL, 901234-02, keeps the eight IEEE-488
      # primitives: each seven bytes above the B series' (CBM2::IEEELayout),
      # with the same file variables in segment 15's zero page. It drives
      # the bus from the same ports, but leaves TPI1's PA2 an input, so its
      # writes to TPI1's port A and its direction register differ in that
      # bit: TALK and LISTEN set DDRA to $3B and PA to $FE, TKSA and ACPTR
      # keep $3D of PA and set DDRA to $C3, ACPTR keeps $3D of PA and sets
      # PA0, and UNTALK and UNLISTEN leave PA $FD before letting ATN go.
      module IEEELayout
        LineStep = KernalTrap::IEEELineStep

        def self.write(address, value) = CBM2::IEEELayout.write(address, value)

        def self.update(address, keep, set) = CBM2::IEEELayout.update(address, keep, set)

        ATTENTION = [write(0xde03, 0x3b), write(0xdc00, 0xff), write(0xdc02, 0xff), write(0xde00, 0xfe),
                     update(0xde00, 0xf7, 0)].freeze
        LISTEN_TO_TALKER = [update(0xde00, 0x3d, 0), write(0xde03, 0xc3), write(0xdc02, 0x00)].freeze

        LINES = KernalTrap::IEEELines.new(
          timer: CBM2::IEEELayout::TIMER, attention: ATTENTION, byte_sent: CBM2::IEEELayout::BYTE_SENT,
          release_attention: CBM2::IEEELayout::RELEASE_ATTENTION, listen_to_talker: LISTEN_TO_TALKER,
          byte_received: [update(0xde00, 0x3d, 0x01)].freeze,
          release: (ATTENTION + CBM2::IEEELayout::BYTE_SENT + [write(0xde00, 0xfd)] + LISTEN_TO_TALKER.drop(1) +
                    CBM2::IEEELayout::RELEASE_ATTENTION).freeze
        )

        LAYOUT = KernalTrap::IEEELayout.new(
          talk: 0xf237, listen: 0xf23b, second: 0xf27b, tksa: 0xf287, ciout: 0xf29e, untalk: 0xf2b2,
          unlisten: 0xf2b6, acptr: 0xf311, overwrites_device: false, device_in_a: true,
          zero_page: CBM2::IEEELayout::ZERO_PAGE, lines: LINES
        )
      end
    end
  end
end
