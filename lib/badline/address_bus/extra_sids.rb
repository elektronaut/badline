# frozen_string_literal: true

module Badline
  class AddressBus
    # The second and third SIDs the SID player fits for a tune written for
    # them, each over its 32 bytes of the I/O area (SIDSlots).
    module ExtraSIDs
      # Fits a SID at the address it was built at, where it takes its 32
      # bytes over from whatever maps there.
      def add_sid(sid)
        @extra_sids << sid
        update_overlays!
      end

      private

      def map_extra_sids
        @extra_sids.each do |sid|
          page = sid.start >> 8
          @read_pages[page] = sid_slots(@read_pages[page]).place(sid)
          @write_pages[page] = sid_slots(@write_pages[page]).place(sid)
        end
      end

      def sid_slots(handler) = handler.is_a?(SIDSlots) ? handler : SIDSlots.new(handler)
    end
  end
end
