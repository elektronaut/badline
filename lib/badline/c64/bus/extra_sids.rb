# frozen_string_literal: true

module Badline
  class C64
    class Bus
      # The second and third SIDs the SID player fits for a tune written for
      # them, each over its 32 bytes of the I/O area (SIDSlots). The SID
      # player's machine has nothing else in I/O 1 and 2, so the rest of a
      # page there reads the open bus.
      #
      # A snapshot holds each in its own keyed module, BL-SID2 onwards in the
      # order they were fitted, with the address it sits at and its model
      # ahead of the SID's own fields.
      module ExtraSIDs
        SID_MODEL_NAMES = %w[mos6581 mos8580].freeze

        # The SIDs fitted past the first, in the order they were fitted.
        attr_reader :extra_sids

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
          @extra_sids << sid
          update_overlays!
        end

        # Takes the extra SIDs out, giving their addresses back to what maps
        # there.
        def remove_extra_sids
          @sid_slots.clear
          @extra_sids.clear
          update_overlays!
        end

        def save_extra_sid_modules(sections)
          @extra_sids.each_with_index do |sid, index|
            sections << Snapshot::Keyed.section("BL-SID#{index + 2}") do |out|
              out.int("address", sid.start).text("model", sid.model.to_s)
              sid.save_fields(out)
            end
          end
          sections
        end

        # Fits the extra SIDs the snapshot's modules hold and loads them. A
        # SID already fitted at the same address stays, on the model the
        # snapshot names, and one the snapshot hasn't comes out. A module
        # whose address no SID fits at is left out, and reported.
        def load_extra_sid_modules(modules)
          addresses = []
          inputs = extra_sid_inputs(modules, addresses)
          models = inputs.map { |input| sid_model_named(input.choice("model", SID_MODEL_NAMES, "mos6581")) }
          refit_sids(addresses, models)
          @extra_sids.each_with_index do |sid, index|
            model = models[index]
            sid.model = model unless sid.model == model
            sid.load_fields(inputs[index])
          end
        end

        private

        def map_extra_sids
          @sid_slots.each { |slots| @read_pages[slots.page] = @write_pages[slots.page] = slots }
        end

        def extra_sid_inputs(modules, taken)
          inputs = []
          number = 2
          input = modules.optional("BL-SID2")
          while input
            address = input.word("address", 0xd420)
            if sid_fits?(address) && !taken.include?(address)
              inputs << input
              taken << address
            else
              input.adjust(format("no SID fits at $%04x, so it's left out", address))
            end
            number += 1
            input = modules.optional("BL-SID#{number}")
          end
          inputs
        end

        # A SID's 32 bytes past the first SID's own, in $D420-$D7FF, or in
        # I/O 1 or 2.
        def sid_fits?(address)
          address.nobits?(0x1f) && ((0xd420..0xd7e0).cover?(address) || (0xde00..0xdfe0).cover?(address))
        end

        def sid_model_named(name) = name == "mos8580" ? :mos8580 : :mos6581

        def refit_sids(addresses, models)
          fitted = @extra_sids.dup
          return if fitted.map(&:start) == addresses

          remove_extra_sids
          addresses.each_with_index do |address, index|
            add_sid(fitted.find { |sid| sid.start == address } || Chips::SID.new(model: models[index], at: address))
          end
        end
      end
    end
  end
end
