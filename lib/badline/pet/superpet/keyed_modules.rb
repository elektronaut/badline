# frozen_string_literal: true

module Badline
  class PET
    class SuperPET < PET
      # The SuperPET as keyed snapshot modules: the 8032's (PET::KeyedModules),
      # then BL-SUPERPET with the board and the 6702 under dongle.*, BL-ACIA
      # and BL-M6809. The traps on the Waterloo ROM's routines go in
      # BL-TRAPDOS under waterloo.*, beside the KERNAL's. Without BL-ACIA or
      # BL-M6809, as from xpet, the unit stays as it is. The CPU switch and
      # the latches say which CPU has the bus, and the CPU that has it
      # settles on its instruction boundary, or in SYNC or CWAI.
      module KeyedModules
        def settled_for_snapshot?
          return super unless @m6809_running

          @m6809.boundary? || @m6809.waiting?
        end

        def save_modules
          sections = super
          board = @board
          dongle = @dongle
          sections << Snapshot::Keyed.section("BL-SUPERPET") do |out|
            board.save_fields(out)
            dongle.save_fields(out, "dongle.")
          end
          sections << Snapshot::Keyed.section("BL-ACIA") { |out| @acia.save_fields(out) }
          sections << Snapshot::Keyed.section("BL-M6809") { |out| @m6809.save_fields(out) }
          sections
        end

        def load_modules(modules)
          super
          board = modules.required("BL-SUPERPET")
          @board.load_fields(board)
          @dongle.load_fields(board, "dongle.")
          acia = modules.optional("BL-ACIA")
          @acia.load_fields(acia) if acia
          m6809 = modules.optional("BL-M6809")
          @m6809.load_fields(m6809) if m6809
          @m6809_running = @board.m6809?
          @board.restored!
          @acia.restored!
          @m6809.restored!
          self
        end

        def save_trap_dos_fields(out)
          super
          @waterloo_traps&.save_fields(out, "waterloo.")
        end

        def load_trap_dos_fields(input, detached: false)
          super
          @waterloo_traps&.load_fields(input, "waterloo.")
        end
      end

      include KeyedModules
    end
  end
end
