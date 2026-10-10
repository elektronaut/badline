# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's sections, each showing a part of the machine's
    # hardware as it stands, in one column: what's there, and under it a
    # row for each thing to do, a setting showing its value on the right,
    # which a press steps on.
    class MenuPages
      include MenuPorts

      TEXT = PauseMenu::TEXT
      DIM = PauseMenu::DIM
      LINE = 12
      COLUMNS = 25
      ROW_WIDTH = 200

      WARNING = 0xff7a6b
      RECENT = %i[recent0 recent1 recent2 recent3 recent4 recent5 recent6 recent7].freeze

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
        @media = MenuMedia.new(media_path, options.writable?)
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
        @painter.text(left, top + 186, problem[0, COLUMNS], WARNING) unless problem.empty?
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
        when :reset then @computer.reset!
        when :power_cycle then @computer.power_cycle!
        else pick_port(action)
        end
      end

      # Whether the machine is a C128, whose F8 switches its screens.
      def c128? = @computer.family == :c128

      private

      def vic20? = @computer.family == :vic20

      # Says in the dim colour that the VIC-20 hasn't got what the page
      # shows.
      def note
        @painter.text(@left, @top, "NOT ON THE VIC-20 YET", DIM)
      end

      def draw_drive
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

      def draw_datasette
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
        return info("RAM EXPANSION", RAM_NAMES.fetch(@computer.ram_configuration)) if vic20?

        cartridge = @computer.address_bus.cartridge
        info("CARTRIDGE", cartridge.nil? ? "" : cartridge.name)
        row("INSERT...", :insert_cartridge)
        row("REMOVE", :remove_cartridge)
        row("FREEZE", :freeze) if !cartridge.nil? && cartridge.freezer? && @computer.family == :c64
        return if @reu_kb.nil?

        skip
        info("RAM EXPANSION", "REU, #{@reu_kb} KB")
      end

      # The SID's model is a setting, and other sound chips have none.
      def draw_sound
        if @sound.on?
          toggle("OUTPUT", :output, [%w[ON MUTED], %i[sound_on mute], @sound.muted? ? 1 : 0])
        else
          info("OUTPUT", "OFF")
        end
        model = @computer.sound_source.model
        return unless SID_MODELS.include?(model)

        toggle("SID", :sid, [%w[6581 8580], %i[sid6581 sid8580], model == :mos8580 ? 1 : 0])
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

      # The C128 names its model and the mode it runs in first.
      def draw_power
        info("MACHINE", "#{@computer.model.name.upcase}, #{@computer.mode.to_s.upcase} MODE") if c128?
        row("RESET", :reset)
        row("POWER CYCLE", :power_cycle)
        skip
        row("QUIT", :quit)
      end

      # A label, and its value under it, or NONE in the dim colour when the
      # value is empty.
      def info(label, value)
        @painter.text(@left, @top, label, DIM)
        if value.empty?
          @painter.text(@left, @top + LINE, "NONE", DIM)
        else
          @painter.text(@left, @top + LINE, Painter.fit(value, COLUMNS), TEXT)
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
