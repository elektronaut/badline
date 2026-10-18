# frozen_string_literal: true

module Badline
  class CBM2
    class Bus
      # Segment 15's RAM, the screen RAM, the RAM board's segments, both
      # segment registers, the last byte on the bus and a cartridge's ROMs
      # by load address, in a keyed snapshot module (BL-RAM). The pages are
      # laid out again once loaded (#restored!). The BASIC and KERNAL ROMs
      # come with the machine.
      module KeyedState
        def save_fields(out)
          @ram.save_fields(out, "system")
          @screen.save_fields(out, "screen")
          @segment_ram.each_with_index { |memory, segment| memory&.save_fields(out, "segment#{segment}") }
          out.int("execution_segment", @execution_segment).int("indirect_segment", @indirect_segment)
          out.int("data", @data)
          out.ints("cartridge.addresses", @cartridge.map(&:start))
          @cartridge.each { |rom| out.bytes("cartridge.#{rom.start}", rom.snapshot) }
        end

        def load_fields(input)
          @ram.load_fields(input, "system")
          @screen.load_fields(input, "screen")
          @segment_ram.each_with_index { |memory, segment| memory&.load_fields(input, "segment#{segment}") }
          @execution_segment = input.masked("execution_segment", @execution_segment, 0x0f)
          @indirect_segment = input.masked("indirect_segment", @indirect_segment, 0x0f)
          @data = input.byte("data", @data)
          @cartridge = input.ints("cartridge.addresses", []).filter_map { |address| cartridge_rom(input, address) }
        end

        def restored! = map_pages

        private

        # The cartridge ROM saved for +address+, in $1000-$7FFF of segment
        # 15, or nil.
        def cartridge_rom(input, address)
          data = input.bytes("cartridge.#{address}", "".b).bytes
          return nil if data.empty? || address < 0x1000 || address + data.length > 0x8000

          ROM.new(data, length: data.length, start: address)
        end
      end

      include KeyedState
    end

    # The machine's own fields in a keyed snapshot module (Snapshot::Keyed,
    # BL-MACHINE): the family, its setup by name (Snapshot::CBM2Setup), the
    # cycle count, where the mains is in its period, and the host's typing
    # still to feed and on_init handlers still to run under host.*. The
    # badline version that wrote it is written for reports and never read.
    module KeyedState
      # How many more on_init handlers the machine a snapshot was taken of had
      # yet to run than this one has. Nil until the machine is restored.
      attr_reader :init_handlers_lost

      # Whether a snapshot saves now (Machine::Settling): the CPU between
      # instructions or jammed.
      def settled_for_snapshot? = @cpu.boundary? || @cpu.jammed?

      # Nothing defers its work past the cycle.
      def settle_chips_for_snapshot = nil

      def save_machine_fields(out)
        out.text("family", "cbm2").text("written_by", VERSION)
        Snapshot::CBM2Setup.of(self).write_fields(out)
        out.int("cycles", @cycles).int("mains_countdown", @mains_countdown).bool("mains_high", @mains_high)
        pending = @pending_keys
        out.ints("host.pending_keys", pending) if pending
        out.int("host.init_pending", @cycles <= @init_threshold ? @init_handlers.length : 0)
      end

      def load_machine_fields(input)
        @cycles = input.int("cycles", @cycles)
        countdown = input.int("mains_countdown", @mains_countdown)
        @mains_countdown = countdown.between?(1, @mains_half_period) ? countdown : @mains_half_period
        @mains_high = input.bool("mains_high", @mains_high)
        pending = input.ints("host.pending_keys", [])
        @pending_keys = pending.empty? ? nil : pending.dup
        @init_handlers_lost = [input.int("host.init_pending", 0) - @init_handlers.length, 0].max
      end
    end

    include KeyedState
  end
end
