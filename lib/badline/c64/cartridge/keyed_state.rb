# frozen_string_literal: true

module Badline
  class C64
    class Cartridge
      # A cartridge's fields in a keyed snapshot module (Snapshot::Keyed,
      # BL-CART): the CRT image it was built from and its jumpers, which
      # build it again (Cartridge.from_fields), the EXROM and GAME lines,
      # its pull on NMI, the button, and where ROML and ROMH point, each by
      # the name of the bank or view it shows (window_labels), and whatever
      # each mapper adds.
      module KeyedState
        def save_fields(out)
          save_setup_fields(out)
          out.int("exrom", @exrom).int("game", @game).bool("nmi", @nmi).bool("button", @button == true)
          save_mapper_fields(out)
          out
        end

        def load_fields(input)
          @exrom = input.masked("exrom", @exrom, 1)
          @game = input.masked("game", @game, 1)
          @nmi = input.bool("nmi", @nmi)
          @button = input.bool("button", false)
          load_mapper_fields(input)
        end

        private

        def save_setup_fields(out)
          out.bytes("crt", Storage::CRTFile.encode(@crt))
          save_jumper_fields(out)
        end

        def save_jumper_fields(_out); end

        def save_mapper_fields(out)
          save_window_fields(out)
        end

        def load_mapper_fields(input)
          load_window_fields(input)
        end

        # The name of each of `windows`, in the same order: bank<N> for the
        # mapper's banks, and empty for erased ROM.
        def window_labels
          banks = @banks
          return [] unless banks

          [*Array.new(banks.length) { |number| "bank#{number}" }, "empty"]
        end

        def save_window_fields(out)
          choices = windows
          return unless choices

          labels = window_labels
          save_window(out, "roml", @roml, choices, labels)
          save_window(out, "romh", @romh, choices, labels)
        end

        def save_window(out, key, window, choices, labels)
          return if window.nil?

          out.text(key, labels.fetch(window_index(window, choices)))
        end

        def load_window_fields(input)
          choices = windows
          return unless choices

          labels = window_labels
          @roml = window_named(input.choice("roml", [*labels, "none"], "none"), choices, labels)
          @romh = window_named(input.choice("romh", [*labels, "none"], "none"), choices, labels)
        end

        def window_named(label, choices, labels)
          index = labels.index(label)
          index.nil? ? nil : choices.fetch(index)
        end
      end

      include KeyedState

      class << self
        # A cartridge built afresh from the CRT image and the jumpers a
        # keyed snapshot module holds, before load_fields puts its state in.
        def from_fields(input)
          kb = input.int("geo_ram_kb", 0)
          return GeoRAM.new(size: kb) if kb.positive?

          crt = Storage::CRTFile.new(bytes: input.bytes("crt", "".b))
          mapper_for(crt).from_jumper_fields(crt, input)
        end

        def from_jumper_fields(crt, _input) = new(crt)
      end

      # Two banks of ROM, one behind each window: roml<N> and romh<N>.
      module SplitBanks
        private

        def window_labels
          [*Array.new(@roml_banks.length) { |number| "roml#{number}" },
           *Array.new(@romh_banks.length) { |number| "romh#{number}" }, "empty"]
        end
      end

      class SuperGames
        include SplitBanks

        private

        def save_mapper_fields(out)
          super
          out.bool("locked", @locked)
        end

        def load_mapper_fields(input)
          super
          @locked = input.bool("locked", @locked)
        end
      end

      class Comal80
        include SplitBanks
      end

      class FinalCartridge3
        include SplitBanks

        private

        def save_mapper_fields(out)
          super
          out.bool("register_visible", @register_visible).bool("phi1_ultimax", @phi1_ultimax)
        end

        def load_mapper_fields(input)
          super
          @io_bank = @roml
          @register_visible = input.bool("register_visible", @register_visible)
          @phi1_ultimax = input.bool("phi1_ultimax", @phi1_ultimax)
        end
      end

      class RGCD
        private

        def save_mapper_fields(out)
          super
          out.bool("disabled", @disabled)
        end

        def load_mapper_fields(input)
          super
          @disabled = input.bool("disabled", @disabled)
        end
      end

      class Zaxxon
        class High
          def save_fields(out)
            out.int("high_bank", [*@banks, EMPTY_BANK].index { |bank| bank.equal?(@bank) }.to_i)
          end

          def load_fields(input)
            choices = [*@banks, EMPTY_BANK]
            @bank = choices.fetch(input.int("high_bank", 0).clamp(0, choices.length - 1))
          end
        end

        private

        def save_mapper_fields(out) = @romh.save_fields(out)

        def load_mapper_fields(input) = @romh.load_fields(input)
      end

      class EpyxFastload
        private

        # How long ago the capacitor was discharged, on the machine's clock.
        def save_mapper_fields(out)
          out.int("discharged_ago", now_cycles - @discharged_at)
        end

        def load_mapper_fields(input)
          @discharged_at = now_cycles - input.int("discharged_ago", now_cycles - @discharged_at)
        end

        def now_cycles
          clock = @clock
          clock ? clock.call : 0
        end
      end

      class ActionReplay
        private

        def window_labels
          ["through", "isolated", "contended", *Array.new(@rom_banks.length) { |number| "rom#{number}" }, "empty"]
        end

        def save_mapper_fields(out)
          super
          out.text("rom", window_labels.fetch(window_index(@rom, windows))).bool("active", @active)
          out.bool("io2_ram", @io2_ram).bytes("ram", @ram_data)
        end

        def load_mapper_fields(input)
          super
          labels = window_labels
          @rom = window_named(input.choice("rom", labels, "rom0"), windows, labels)
          @active = input.bool("active", @active)
          @io2_ram = input.bool("io2_ram", @io2_ram)
          input.bytes_into("ram", @ram_data)
        end
      end

      class KCSPower
        private

        def save_mapper_fields(out) = out.bytes("io_ram", @io_ram)

        def load_mapper_fields(input) = input.bytes_into("io_ram", @io_ram)
      end

      class Pagefox
        private

        def window_labels
          [*Array.new(@roml_banks.length) { |number| "roml#{number}" },
           *Array.new(@romh_banks.length) { |number| "romh#{number}" },
           *Array.new(@ram_banks.length) { |number| "ram#{number}" }, "open_bus", "empty"]
        end

        def save_mapper_fields(out)
          super
          @ram_banks.each_with_index { |ram, number| out.bytes("ram#{number}.data", ram.data) }
        end

        def load_mapper_fields(input)
          super
          @ram_banks.each_with_index { |ram, number| input.bytes_into("ram#{number}.data", ram.data) }
        end
      end

      class GeoRAM
        private

        def save_setup_fields(out) = out.int("geo_ram_kb", @size)

        def save_mapper_fields(out)
          out.bytes("ram", @ram_data).int("block", @block).int("page", @page).int("window", @window)
        end

        def load_mapper_fields(input)
          input.bytes_into("ram", @ram_data)
          @block = input.int("block", @block)
          @page = input.int("page", @page)
          @window = input.int("window", @window)
        end
      end

      class Flash
        # The array, the command state by name, how far through a command
        # sequence, the toggle bit, a timed operation's end in cycles from
        # now, and the windows handed out so far, under `prefix`.
        module KeyedState
          STATE_NAMES = STATES.map(&:to_s).freeze

          def save_fields(out, prefix)
            out.bytes("#{prefix}data", @data).text("#{prefix}state", @state.to_s)
            out.text("#{prefix}base_state", @base_state.to_s).int("#{prefix}cycle", @cycle)
            out.int("#{prefix}toggle", @toggle)
            done_at = @done_at
            out.int("#{prefix}done_in", done_at - @clock.call) unless done_at.nil?
            out.optional_int("#{prefix}programmed", @programmed).optional_int("#{prefix}remaining", @remaining)
            sectors = @erasing_sectors
            out.ints("#{prefix}erasing_sectors", sectors) if sectors
            out.ints("#{prefix}windows", @windows.keys).ints("#{prefix}status_windows", @status_windows.keys)
          end

          def load_fields(input, prefix)
            input.bytes_into("#{prefix}data", @data)
            @state = state_named(input.choice("#{prefix}state", STATE_NAMES, "read"))
            @base_state = state_named(input.choice("#{prefix}base_state", STATE_NAMES, "read"))
            @cycle = input.int("#{prefix}cycle", @cycle)
            @toggle = input.int("#{prefix}toggle", @toggle)
            done_in = input.optional_int("#{prefix}done_in")
            @done_at = done_in.nil? ? nil : @clock.call + done_in
            @programmed = input.optional_int("#{prefix}programmed")
            @remaining = input.optional_int("#{prefix}remaining")
            sectors = input.ints("#{prefix}erasing_sectors", [])
            @erasing_sectors = sectors.empty? ? nil : sectors.dup
            rebuild_windows(input.ints("#{prefix}windows", []), input.ints("#{prefix}status_windows", []))
          end

          private

          def state_named(name)
            STATES.find { |state| state.to_s == name } || :read
          end
        end

        include KeyedState
      end

      class GMod2
        private

        def save_mapper_fields(out)
          out.int("bank", @bank).bool("flash_writes", @flash_writes)
          @flash.save_fields(out, "flash.")
        end

        def load_mapper_fields(input)
          @bank = input.int("bank", @bank)
          @flash_writes = input.bool("flash_writes", @flash_writes)
          @flash.load_fields(input, "flash.")
          @roml = @flash.window(@bank * BANK_SIZE)
        end
      end

      class EasyFlash
        private

        def save_mapper_fields(out)
          out.int("bank", @bank).int("control", @control).bytes("io_ram", @io_ram)
          @low_flash.save_fields(out, "flash_low.")
          @high_flash.save_fields(out, "flash_high.")
        end

        def load_mapper_fields(input)
          @bank = input.int("bank", @bank)
          @control = input.byte("control", @control)
          input.bytes_into("io_ram", @io_ram)
          @low_flash.load_fields(input, "flash_low.")
          @high_flash.load_fields(input, "flash_high.")
          map_bank
        end
      end

      class RetroReplay
        CONFIG_NAMES = CONTROL_MODES.map(&:to_s).freeze

        # The flash and bank jumpers, as the board has them set.
        def self.from_jumper_fields(crt, input)
          new(crt, flash_jumper: input.bool("jumper.flash", false), bank_jumper: input.bool("jumper.bank", false))
        end

        private

        def save_jumper_fields(out)
          out.bool("jumper.flash", @flash_jumper).bool("jumper.bank", @bank_jumper)
        end

        def save_mapper_fields(out)
          out.bool("active", @active).bool("frozen", @frozen).bool("phi1_ultimax", @phi1_ultimax)
          out.bool("ram_enabled", @ram_enabled).bool("ram_at_a000", @ram_at_a000).bool("allow_bank", @allow_bank)
          out.bool("no_freeze", @no_freeze).bool("reu_mapping", @reu_mapping).bool("write_once", @write_once)
          out.int("bank", @bank).text("config", @config.to_s)
          @ram_data.each_with_index { |data, number| out.bytes("ram#{number}", data) }
          @flash.save_fields(out, "flash.")
        end

        def load_mapper_fields(input)
          load_flag_fields(input)
          @bank = input.int("bank", @bank)
          config = input.choice("config", CONFIG_NAMES, "rom8k")
          @config = CONTROL_MODES.find { |mode| mode.to_s == config } || :rom8k
          @ram_data.each_with_index { |data, number| input.bytes_into("ram#{number}", data) }
          @flash.load_fields(input, "flash.")
          map_windows
        end

        def load_flag_fields(input)
          @active = input.bool("active", @active)
          @frozen = input.bool("frozen", @frozen)
          @phi1_ultimax = input.bool("phi1_ultimax", @phi1_ultimax)
          @ram_enabled = input.bool("ram_enabled", @ram_enabled)
          @ram_at_a000 = input.bool("ram_at_a000", @ram_at_a000)
          @allow_bank = input.bool("allow_bank", @allow_bank)
          @no_freeze = input.bool("no_freeze", @no_freeze)
          @reu_mapping = input.bool("reu_mapping", @reu_mapping)
          @write_once = input.bool("write_once", @write_once)
        end
      end
    end
  end
end
