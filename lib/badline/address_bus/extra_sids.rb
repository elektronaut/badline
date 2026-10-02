# frozen_string_literal: true

module Badline
  class AddressBus
    # The second and third SIDs the SID player fits for a tune written for
    # them, each over its 32 bytes of the I/O area (SIDSlots). The SID
    # player's machine has nothing else in I/O 1 and 2, so the rest of a
    # page there reads the open bus.
    module ExtraSIDs
      # Fits a SID at the address it was built at, where it takes its 32
      # bytes over from whatever maps there.
      def add_sid(sid)
        page = sid.start >> 8
        slots = @sid_slots.find { |candidate| candidate.page == page }
        if slots.nil?
          slots = SIDSlots.new(page, @sid, @open_bus)
          @sid_slots << slots
        end
        slots.place(sid)
        update_overlays!
      end

      private

      def map_extra_sids
        @sid_slots.each { |slots| @read_pages[slots.page] = @write_pages[slots.page] = slots }
      end
    end
  end
end
