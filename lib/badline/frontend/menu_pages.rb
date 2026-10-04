# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's sections, each showing a part of the machine's
    # hardware as it stands, in one column: what's there, and under it a
    # row for each thing to do, a setting showing its value on the right,
    # which a press steps on.
    class MenuPages
      TEXT = PauseMenu::TEXT
      DIM = PauseMenu::DIM
      LINE = 12
      COLUMNS = 25
      ROW_WIDTH = 200

      WARNING = 0xff7a6b
      RECENT = %i[recent0 recent1 recent2 recent3 recent4 recent5 recent6 recent7].freeze

      PORT_DEVICES = %i[joystick mouse paddles].freeze
      PORT_NAMES = %w[JOY MOUSE PADDLES].freeze
      PORT_ACTIONS = [%i[port1_joystick port1_mouse port1_paddles], %i[port2_joystick port2_mouse port2_paddles]].freeze
      POTS = [%i[none mouse1 paddles1], %i[none mouse2 paddles2]].freeze

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
        when :sid6581, :sid8580 then @computer.sid.model = action == :sid8580 ? :mos8580 : :mos6581
        when :reset then @computer.reset!
        when :power_cycle then @computer.power_cycle!
        else pick_port(action)
        end
      end

      private

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
        info("DEVICE", @computer.drive1541.nil? ? "FAST LOADING" : "1541, TRUE DRIVE")
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
        cartridge = @computer.address_bus.cartridge
        info("CARTRIDGE", cartridge.nil? ? "" : cartridge.name)
        row("INSERT...", :insert_cartridge)
        row("REMOVE", :remove_cartridge)
        row("FREEZE", :freeze) if !cartridge.nil? && cartridge.freezer?
        return if @reu_kb.nil?

        skip
        info("RAM EXPANSION", "REU, #{@reu_kb} KB")
      end

      def draw_ports
        toggle("PORT 1", :port1, [PORT_NAMES, PORT_ACTIONS[0], PORT_DEVICES.index(port_device(1))])
        toggle("PORT 2", :port2, [PORT_NAMES, PORT_ACTIONS[1], PORT_DEVICES.index(port_device(2))])
        joystick = @controls.joystick_mode?
        toggle("KEYS", :keys, [%w[C64 JOYSTICK], %i[keys_c64 keys_joystick], joystick ? 1 : 0])
        return unless joystick

        row("SWAP JOYSTICKS", :swap)
        skip
        arrows = @controls.arrows_port
        info("ARROWS, SPACE", "PORT #{arrows}")
        info("WASD, LEFT SHIFT", "PORT #{3 - arrows}")
      end

      def draw_sound
        if @sound.on?
          toggle("OUTPUT", :output, [%w[ON MUTED], %i[sound_on mute], @sound.muted? ? 1 : 0])
        else
          info("OUTPUT", "OFF")
        end
        toggle("SID", :sid, [%w[6581 8580], %i[sid6581 sid8580], @computer.sid.model == :mos8580 ? 1 : 0])
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

      def draw_power
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

      def keys(mode) = @controls.joystick_mode = mode == :joystick

      def port_device(port)
        index = POTS[port - 1].index(@controls.pot)
        index.nil? ? :joystick : PORT_DEVICES[index]
      end

      # Plugs the device a choice such as :port1_mouse names into its port.
      def pick_port(action)
        index = PORT_ACTIONS[0].include?(action) ? 0 : 1
        choice = PORT_ACTIONS[index].index(action)
        plug_device(index + 1, choice) unless choice.nil? || choice == PORT_DEVICES.index(port_device(index + 1))
      end

      # Plugs PORT_DEVICES[choice] into the port. A joystick there takes out
      # the pot device.
      def plug_device(port, choice)
        @controls.plug(POTS[port - 1][choice])
      end
    end
  end
end
