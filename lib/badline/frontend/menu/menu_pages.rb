# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's sections, each showing a part of the machine's
    # hardware as it stands, in one column: what's there, and under it a
    # row for each thing to do, a setting showing its value on the right,
    # which a press steps on.
    class MenuPages
      include MenuPorts

      LINE = 12
      COLUMNS = 25
      ROW_WIDTH = 200

      # The KIM-1's settings on its PANEL page (MenuPorts).
      KIM1_SETTINGS = %i[sst_off sst_on keypad teletype irq_open irq_wired pb7_out pa0_speaker].freeze

      RECENT = %i[recent0 recent1 recent2 recent3 recent4 recent5 recent6 recent7].freeze

      # The SuperPET's switches: SW2 picks the CPU and SW1 protects the
      # bank RAM, each at PROG left to the system latch.
      CPU_SWITCH = [%w[6502 6809 PROG], %i[cpu6502 cpu6809 cpu_prog]].freeze
      RAM_SWITCH = [%w[R/W READ PROG], %i[bank_rw bank_read bank_prog]].freeze

      SID_MODELS = %i[mos6581 mos8580].freeze
      RAM_NAMES = {
        unexpanded: "", "3k": "3K", "8k": "8K", "16k": "16K", "24k": "24K", "32k": "32K",
        all: "35K, ALL BLOCKS"
      }.freeze

      # The disks, tapes and cartridges the pages put in and take out.
      attr_reader :media

      def initialize(painter, buttons, media_path, options, snapshots)
        @snapshots = snapshots
        @recent = []
        @painter = painter
        @buttons = buttons
        @media = MenuMedia.new(media_path, options.writable?, options.cartridges)
        @reu_kb = options.reu
        @computer = nil
        @controls = nil
        @sound = nil
        @left = 0
        @top = 0
      end

      # The machine the pages show and change.
      def machine(computer, controls, sound)
        @computer = computer
        @media.computer = computer
        @controls = controls
        @sound = sound
      end

      def draw(page, left, top)
        problem = @media.problem
        @painter.text(left, top + 186, problem[0, COLUMNS], MenuTheme::WARNING) unless problem.empty?
        @left = left
        @top = top
        case page
        when :drive then draw_drive
        when :datasette then draw_datasette
        when :expansion then draw_expansion
        when :ports then draw_ports
        when :sound then draw_sound
        when :snapshots then draw_snapshots
        else draw_power
        end
      end

      # The path of the quicksave or autosave a RECENT action stands for.
      def recent(action) = @recent[RECENT.index(action)].to_s

      def perform(action)
        case action
        when :eject_disk, :previous_disk, :next_disk, :protect, :unprotect then @media.drive(action)
        when :tape_stop then @computer.datasette.stop!
        when :tape_down then @computer.datasette.play!
        when :tape_rewind then @computer.datasette.rewind
        when :tape_eject then @computer.datasette.eject
        when :keys_c64, :keys_joystick then keys(action == :keys_c64 ? :keyboard : :joystick)
        when :swap then @controls.swap_ports
        when :sound_on, :mute then @sound.toggle_mute unless @sound.muted? == (action == :mute)
        when :sid6581, :sid8580 then @computer.sound_source.model = action == :sid8580 ? :mos8580 : :mos6581
        when :cpu6502, :cpu6809, :cpu_prog then switch_cpu(action)
        when :bank_rw, :bank_read, :bank_prog then switch_bank_ram(action)
        when :reset then @computer.reset!
        when :power_cycle then @computer.power_cycle!
        when *KIM1_SETTINGS then kim1_setting(action)
        else pick_port(action)
        end
      end

      # Whether the machine is a C128, whose F8 switches its screens.
      def c128? = @computer.family == :c128

      # Whether the machine is a PET, whose ports page shows its keyboard.
      def pet? = @computer.family == :pet

      # Whether the machine is a CBM-II, whose ports page shows its keyboard
      # too.
      def cbm2? = @computer.family == :cbm2

      # Whether the machine is the CBM-II's B series, whose ports page is
      # its keyboard's alone.
      def b_series? = cbm2? && !Controls.p500?(@computer)

      # Whether the machine is a KIM-1, whose ports page is its panel's.
      def kim1? = @computer.family == :kim1

      private

      def vic20? = @computer.family == :vic20

      def plus4? = @computer.family == :plus4

      def draw_drive
        return info("DRIVE", "") if kim1?

        media = @media
        inserted = media.inserted?
        set = inserted ? media.disk_set : []
        place = set.size < 2 ? "" : " #{set.index(media.disk_path).to_i + 1} OF #{set.size}"
        info("DISK#{place}", inserted ? File.basename(media.disk_path) : "")
        row("INSERT...", :insert_disk)
        row("EJECT", :eject_disk)
        unless set.size < 2
          row("PREVIOUS DISK", :previous_disk)
          row("NEXT DISK", :next_disk)
        end
        toggle("WRITABLE", :writable, [%w[OFF ON], %i[protect unprotect], media.writable? ? 1 : 0])
        skip
        drive = @computer.true_drive
        info("DEVICE", drive.nil? ? "FAST LOADING" : "#{drive.model_name}, TRUE DRIVE")
      end

      # The CBM-II and the KIM-1 have no datasette.
      def draw_datasette
        return info("TAPE", "") if cbm2? || kim1?

        datasette = @computer.datasette
        tape = datasette.tape
        info("TAPE", tape.nil? ? "" : File.basename(tape.path))
        row("INSERT...", :insert_tape)
        row("EJECT", :tape_eject)
        toggle("PLAY", :tape_play, [%w[UP DOWN], %i[tape_stop tape_down], datasette.playing? ? 1 : 0])
        row("REWIND", :tape_rewind)
        skip
        info("MOTOR", datasette.motor? ? "ON" : "OFF")
      end

      def draw_expansion
        return draw_pet_memory if pet?
        return info("RAM", "#{@computer.model.ram_kb}K") if cbm2?
        return info("RAM", "1K") if kim1?

        info("CARTRIDGE", @media.cartridge_name)
        return info("RAM EXPANSION", RAM_NAMES.fetch(@computer.ram_configuration)) if vic20?

        row("INSERT...", :insert_cartridge)
        row("REMOVE", :remove_cartridge)
        return if plus4?

        cartridge = @computer.address_bus.cartridge
        row("FREEZE", :freeze) if !cartridge.nil? && cartridge.freezer? && @computer.family == :c64
        return if @reu_kb.nil?

        skip
        info("RAM EXPANSION", "REU, #{@reu_kb} KB")
      end

      # The SID's model is a setting, the C64's SID's or a Plus/4's SID
      # card's, and other sound chips have none.
      def draw_sound
        if @sound.on?
          toggle("OUTPUT", :output, [%w[ON MUTED], %i[sound_on mute], @sound.muted? ? 1 : 0])
        else
          info("OUTPUT", "OFF")
        end
        model = @computer.sound_source.model
        return unless SID_MODELS.include?(model)

        toggle(plus4? ? "SID CARD" : "SID", :sid, [%w[6581 8580], %i[sid6581 sid8580], model == :mos8580 ? 1 : 0])
      end

      # The PET's memory: its RAM, the 8096's 64K board, and the 8296's
      # 128K with the jumpers that put RAM under its ROMs.
      def draw_pet_memory
        model = @computer.model
        return draw_8296_memory if model.cbm8296?

        info("RAM", "#{@computer.ram_kb}K")
        return info("BANK RAM", "64K, BANK #{@computer.board.bank} AT $9000") if model.superpet?

        info("EXPANSION RAM", model.expansion ? "64K BOARD" : "")
      end

      def draw_8296_memory
        info("RAM", "128K, 64K OF IT BANKED")
        info("JUMPERS", @computer.jumpers.join(", ").upcase)
      end

      # Saving now and by name, loading a named save, and the quicksaves
      # and autosaves, newest first, which a press loads.
      def draw_snapshots
        row("QUICKSAVE", :quicksave_now)
        row("SAVE...", :save_as)
        row("LOAD...", :load_save)
        skip
        saves = (@snapshots.list("quicksaves") + @snapshots.list("autosaves")).sort_by { |path| -File.mtime(path).to_f }
        @recent = saves.first(RECENT.size)
        @recent.each_with_index do |path, index|
          kind = File.basename(path).start_with?("autosave") ? "AUTOSAVE" : "QUICKSAVE"
          row(kind, RECENT[index], @snapshots.time_of(path))
        end
      end

      # The C128 names its model and the mode it runs in first, the Plus/4,
      # the PET and the CBM-II their model and RAM, the Plus/4 its RAM
      # expansion if it has one, and the CBM-II its KERNAL, the B series'
      # 901244 or the P500's 901234.
      def draw_power
        info("MACHINE", "#{@computer.model.name.upcase}, #{@computer.mode.to_s.upcase} MODE") if c128?
        info("MACHINE", @computer.model_label.upcase) if pet? || cbm2? || kim1?
        info("KERNAL", "#{Controls.p500?(@computer) ? 901_234 : 901_244}-#{@computer.kernal.upcase}") if cbm2?
        draw_superpet_switches if pet? && @computer.superpet?
        if plus4?
          info("MACHINE", @computer.model_label)
          expansion = @computer.ram_expansion_label
          info("RAM EXPANSION", expansion) if expansion
        end
        row("RESET", :reset)
        row("POWER CYCLE", :power_cycle)
        skip
        row("QUIT", :quit)
      end

      # The SuperPET's CPU switch, which a move applies with a reset, and its
      # bank RAM switch, which applies at once, with the CPU that has the
      # bus.
      def draw_superpet_switches
        board = @computer.board
        toggle("CPU SWITCH", :cpu_switch, [*CPU_SWITCH, PET::SuperPET::Board::CPU_SWITCH.index(board.cpu_switch)])
        toggle("RAM SWITCH", :ram_switch, [*RAM_SWITCH, PET::SuperPET::Board::RAM_SWITCH.index(board.ram_switch)])
        info("RUNNING", @computer.m6809_running? ? "6809, WATERLOO" : "6502, BASIC 4")
      end

      def switch_cpu(action)
        position = PET::SuperPET::Board::CPU_SWITCH[CPU_SWITCH[1].index(action)]
        @computer.switch_cpu(position) unless position == @computer.board.cpu_switch
      end

      def switch_bank_ram(action)
        @computer.switch_bank_ram(PET::SuperPET::Board::RAM_SWITCH[RAM_SWITCH[1].index(action)])
      end

      # A label, and its value under it, or NONE in the dim colour when the
      # value is empty.
      def info(label, value)
        @painter.text(@left, @top, label, MenuTheme::DIM)
        if value.empty?
          @painter.text(@left, @top + LINE, "NONE", MenuTheme::DIM)
        else
          @painter.text(@left, @top + LINE, Painter.fit(value, COLUMNS), MenuTheme::TEXT)
        end
        @top += (LINE * 2) + 6
      end

      def row(label, action, value = "")
        @buttons.row([@left, @top, ROW_WIDTH], label, action, value)
        @top += Buttons::HEIGHT + 2
      end

      def toggle(label, action, choices)
        @buttons.toggle([@left, @top, ROW_WIDTH], label, action, choices)
        @top += Buttons::HEIGHT + 2
      end

      def skip
        @top += LINE
      end
    end
  end
end
