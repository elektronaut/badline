# frozen_string_literal: true

module Badline
  class CBM2
    # Where the B series KERNALs, 901244-04a and -03b, keep the eight
    # IEEE-488 primitives, their file variables in segment 15, and the
    # steps they take on the bus's lines (KernalTrap::IEEELayout). TALK and
    # LISTEN take the device in A.
    #
    # The KERNAL drives the bus from TPI1's port A at $DE00 (PA3 ATN, PA4
    # DAV, PA5 EOI, PA6 NDAC, PA7 NRFD, PA0-PA2 the transceivers'
    # directions) and the CIA's port A at $DC00, the data lines inverted.
    # TALK and LISTEN set both ports' directions for sending and pull ATN
    # low, TKSA and ACPTR turn NRFD, NDAC and the data lines round for
    # listening, and each handshake times out on CIA timer B, which the
    # ROM starts with $FF to $DC07 and $11 to $DC0F and acknowledges by
    # reading $DC0D. ACPTR leaves port A as TKSA does, without touching
    # the directions. 901244-03b differs from -04a in setting PA0 where -04a
    # clears it, at the end of UNTALK, UNLISTEN and ACPTR.
    module IEEELayout
      LineStep = KernalTrap::IEEELineStep

      # A write of +value+ to +address+.
      def self.write(address, value) = LineStep.new(address:, keep: 0, set: value)

      # +address+'s bits in +keep+, ORed with +set+.
      def self.update(address, keep, set) = LineStep.new(address:, keep:, set:)

      TIMER = [write(0xdc07, 0xff), write(0xdc0f, 0x11),
               LineStep.new(address: 0xdc0d, keep: KernalTrap::IEEE_LINE_READ, set: 0)].freeze
      ATTENTION = [write(0xde03, 0x3f), write(0xdc00, 0xff), write(0xdc02, 0xff), write(0xde00, 0xfa),
                   update(0xde00, 0xf7, 0)].freeze
      BYTE_SENT = [update(0xde00, 0xff, 0x12), write(0xdc00, 0xff)].freeze
      RELEASE_ATTENTION = [update(0xde00, 0xff, 0x08)].freeze
      LISTEN_TO_TALKER = [update(0xde00, 0x39, 0), write(0xde03, 0xc7), write(0xdc02, 0x00)].freeze

      # The end of UNTALK and UNLISTEN, which leaves PA $F8, or $F9 on
      # 901244-03b, before letting ATN go, and the end of ACPTR, which
      # leaves PA0 clear, or set on 901244-03b.
      def self.lines(release)
        KernalTrap::IEEELines.new(
          timer: TIMER, attention: ATTENTION, byte_sent: BYTE_SENT, release_attention: RELEASE_ATTENTION,
          listen_to_talker: LISTEN_TO_TALKER, byte_received: [update(0xde00, 0x39, release & 0x01)].freeze,
          release: (ATTENTION + BYTE_SENT + [write(0xde00, release)] + LISTEN_TO_TALKER.drop(1) +
                    RELEASE_ATTENTION).freeze
        )
      end

      # The file variables in segment 15's zero page: the file name's
      # pointer at $90, SAVE's start at $99 and its end at $96, ST at $9C,
      # FNLEN at $9D, FA at $9F, SA at $A0 and VERIFY at $035F.
      ZERO_PAGE = KernalTrap::ZeroPage.new(
        status: 0x9c, verify: 0x035f, start_address: 0x99, end_address: 0x96, filename_length: 0x9d,
        secondary_address: 0xa0, device: 0x9f, filename_address: 0x90, save_start: 0x99, load_address: 0x99
      )

      def self.layout(release)
        KernalTrap::IEEELayout.new(
          talk: 0xf230, listen: 0xf234, second: 0xf274, tksa: 0xf280, ciout: 0xf297, untalk: 0xf2ab,
          unlisten: 0xf2af, acptr: 0xf30a, overwrites_device: false, device_in_a: true, zero_page: ZERO_PAGE,
          lines: lines(release)
        )
      end

      # By the KERNAL's name in Model::KERNALS.
      LAYOUTS = { "04a" => layout(0xf8), "03b" => layout(0xf9) }.freeze
    end
  end
end
