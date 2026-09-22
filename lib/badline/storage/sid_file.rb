# frozen_string_literal: true

module Badline
  module Storage
    # PSID/RSID tunes: a memory image plus the addresses of the routines
    # that initialise it and produce one frame of music.
    class SIDFile
      include IntegerHelper

      class FormatError < StandardError; end

      V1_HEADER_SIZE = 0x76

      # The 6502 stub that starts a tune: call init with the song number,
      # point the KERNAL's IRQ vector at a raster handler that calls play,
      # and return to whatever SYSed it. Both calls are wrapped in the `$01`
      # save, bank and restore that puts the tune's own RAM under the CPU.
      #
      #         jmp boot
      # irq:    lda #$01
      #         sta $d019
      #         lda $01
      #         pha
      #         lda #iomap
      #         sta $01
      #         jsr play
      #         pla
      #         sta $01
      #         jmp $ea31
      # boot:   sei
      #         lda $01
      #         pha
      #         lda #iomap
      #         sta $01
      #         lda #song
      #         jsr init
      #         pla
      #         sta $01
      #         lda #$7f
      #         sta $dc0d
      #         lda $dc0d
      #         lda $d011
      #         and #$7f
      #         sta $d011
      #         lda #$00
      #         sta $d012
      #         lda #$01
      #         sta $d019
      #         sta $d01a
      #         lda #<irq
      #         sta $0314
      #         lda #>irq
      #         sta $0315
      #         cli
      #         rts
      class Driver
        include IntegerHelper

        IRQ_VECTOR = 0x0314
        KERNAL_IRQ = 0xea31
        CIA1_ICR = 0xdc0d
        RASTER_IRQ_STATUS = 0xd019

        def initialize(tune, song:, base:)
          @tune = tune
          @song = song
          @base = base
        end

        def bytes
          @bytes ||= playing? ? jmp(boot_address) + handler + boot : boot
        end

        private

        def playing? = @tune.play_address.positive?

        def handler_address = @base + jmp(0).length

        def boot_address = handler_address + handler.length

        def handler
          @handler ||= lda_imm(0x01) + sta_abs(RASTER_IRQ_STATUS) +
                       banked(@tune.play_address, jsr(@tune.play_address)) +
                       jmp(KERNAL_IRQ)
        end

        def boot
          [0x78] +
            banked(@tune.init_address, lda_imm(@song) + jsr(@tune.init_address)) +
            raster_irq + [0x58, 0x60]
        end

        # Tunes live under the ROMs as often as not, so a call has to bank out
        # whatever covers the routine first. The 6510 port at `$01` is RAM to
        # nobody, so saving it across the call leaves the caller's banking —
        # and with it the I/O the rest of the stub writes to — as it was.
        def banked(address, call)
          bank = @tune.bank_for(address)
          return call unless bank

          lda_zp(0x01) + [0x48] + lda_imm(bank) + sta_zp(0x01) +
            call + [0x68] + sta_zp(0x01)
        end

        def raster_irq
          return [] unless playing?

          mask_cia1 + arm_raster + install_vector
        end

        # Leaves the raster as the only interrupt source.
        def mask_cia1
          lda_imm(0x7f) + sta_abs(CIA1_ICR) + lda_abs(CIA1_ICR)
        end

        def arm_raster
          lda_abs(0xd011) + [0x29, 0x7f] + sta_abs(0xd011) +
            lda_imm(0x00) + sta_abs(0xd012) +
            lda_imm(0x01) + sta_abs(RASTER_IRQ_STATUS) + sta_abs(0xd01a)
        end

        def install_vector
          lda_imm(low_byte(handler_address)) + sta_abs(IRQ_VECTOR) +
            lda_imm(high_byte(handler_address)) + sta_abs(IRQ_VECTOR + 1)
        end

        def lda_imm(value) = [0xa9, value]
        def lda_zp(addr) = [0xa5, addr]
        def sta_zp(addr) = [0x85, addr]
        def lda_abs(addr) = [0xad, low_byte(addr), high_byte(addr)]
        def sta_abs(addr) = [0x8d, low_byte(addr), high_byte(addr)]
        def jsr(addr) = [0x20, low_byte(addr), high_byte(addr)]
        def jmp(addr) = [0x4c, low_byte(addr), high_byte(addr)]
      end

      attr_reader :format

      def initialize(path)
        @bytes = File.binread(path).bytes
        @format = @bytes[0, 4].pack("C*")
        raise FormatError, "Missing PSID or RSID signature" unless %w[PSID RSID].include?(@format)
        raise FormatError, "Truncated header" if truncated?
        raise FormatError, "No tune data" if data.empty?
      end

      def version = word(0x04)
      def data_offset = word(0x06)
      def play_address = word(0x0c)
      def songs = [word(0x0e), 1].max
      def start_song = word(0x10).clamp(1, songs)
      def speed = (word(0x12) << 16) + word(0x14)
      def name = text(0x16)
      def author = text(0x36)
      def released = text(0x56)
      def flags = version > 1 ? word(V1_HEADER_SIZE) : 0
      def init_address = word(0x0a).nonzero? || load_address
      def end_address = load_address + data.length
      def psid? = @format == "PSID"

      # The `$01` value a routine at `address` has to run under, following
      # libsidplayfp's iomap: RAM under BASIC from `$a000`, RAM under both
      # ROMs and no I/O for a routine in the I/O window itself, RAM under the
      # KERNAL from `$e000`. An RSID tune banks itself and gets nil.
      def bank_for(address)
        return unless psid?
        return 0x37 if address < 0xa000
        return 0x36 if address < 0xd000
        return 0x34 if address < 0xe000

        0x35
      end

      # A zero load address puts the real one in the first two bytes of
      # the body, PRG style.
      def load_address
        @load_address ||= word(0x08).nonzero? || uint16(body[0].to_i, body[1].to_i)
      end

      def data
        @data ||= body.drop(word(0x08).zero? ? 2 : 0).first(0x10000 - load_address)
      end

      # A set speed bit asks for CIA timer pacing instead of a raster IRQ;
      # the driver paces everything off the raster either way.
      def cia_timed?(song = start_song)
        speed[[song - 1, 31].min] == 1
      end

      def driver_address
        @driver_address ||= candidates.find { |addr| !overlaps?(addr) } ||
                            raise(FormatError, "No free RAM for the player")
      end

      def driver(song: start_song)
        Driver.new(self, song: song.clamp(1, songs) - 1, base: driver_address).bytes
      end

      private

      def truncated?
        @bytes.length < V1_HEADER_SIZE || @bytes.length < data_offset
      end

      def body
        @body ||= @bytes[data_offset..] || []
      end

      # The tape buffer and the free block below the stack page, neither
      # of which BASIC touches.
      def candidates
        [relocation_address, 0x0334, 0x02a7].compact
      end

      def relocation_address
        page = version > 1 ? @bytes[0x78].to_i : 0
        return if page.zero? || page == 0xff

        page << 8
      end

      def overlaps?(addr)
        addr < end_address && load_address < addr + driver_size
      end

      def driver_size
        @driver_size ||= Driver.new(self, song: 0, base: 0).bytes.length
      end

      def text(offset)
        @bytes[offset, 32].take_while(&:positive?)
                          .pack("C*")
                          .force_encoding(Encoding::ISO_8859_1)
                          .encode(Encoding::UTF_8)
      end

      # Header fields are big-endian, unlike everything else the 6502 sees.
      def word(offset)
        uint16(@bytes[offset + 1], @bytes[offset])
      end
    end
  end
end
