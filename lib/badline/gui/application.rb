# frozen_string_literal: true

module Badline
  module GUI
    class Application
      TITLE = "Badline"
      TOGGLE_SYM = SDL::KEY_TAB
      MUTE_SYM = SDL::KEY_F10
      SAVE_SYM = SDL::KEY_F11
      RESTORE_SYM = SDL::KEY_F12
      HOST_SYMS = [TOGGLE_SYM, MUTE_SYM, SAVE_SYM, RESTORE_SYM].freeze
      REVERSE_MOD = SDL::KMOD_SHIFT

      SHARED_KEYS = %i[cursor_up cursor_left cursor_h cursor_v space w a s d lshift].freeze

      # Tab steps through the input modes and shift-Tab back; the title bar
      # names the live one. The pot devices appear once per control port, since
      # games disagree on which one they read.
      MODES = {
        keyboard: nil, joystick: "JOY",
        mouse1: "MOUSE 1", mouse2: "MOUSE 2",
        paddles1: "PADDLE 1", paddles2: "PADDLE 2"
      }.freeze

      # Both pot devices take their input from the host mouse. Motion turns the
      # paddle knobs or steps the 1351's counters, and the host buttons go to
      # whichever lines the device puts them on.
      POT_DEVICES = {
        mouse1: [Input::Mouse1351, 1], mouse2: [Input::Mouse1351, 2],
        paddles1: [Input::Paddles, 1], paddles2: [Input::Paddles, 2]
      }.freeze
      MOUSE_BUTTONS = { 1 => :left, 3 => :right }.freeze

      # The machine options (sid_model:, reu:, true_drive:, ntsc:) build
      # the machine: reu plugs in an REU of that many K, true_drive puts a
      # true 1541 on device 8, and ntsc makes it an NTSC C64. The media
      # options (autostart:, song:, disk:) go to Media.attach.
      def initialize(media_path: nil, machine: {}, sound: false, verbose: false, **media)
        @verbose = verbose
        @snapshots = Snapshots.new
        @computer = @snapshots.boot(media_path, machine, media)

        @mode = :keyboard
        @pot_device = nil
        @panes = panes
        @stream = open_stream if sound
        @paced = ENV["NOVSYNC"].nil?
        @window = Window.new(
          title: TITLE,
          width: canvas_width, height: canvas_height,
          vsync: @paced && !@stream
        )
        @gamepads = Gamepads.new(@computer)
        @gamepads.names.each { |name| report "Gamepad: #{name}" }
        fit_frame
      end

      def run
        @running = true
        while @running
          handle_events
          @gamepads.poll
          @cycles_per_frame.times { @computer.cycle! }
          @stream&.feed
          @window.draw(@panes)
          @stream.pace(@frame_seconds) if @stream && @paced
        end
      ensure
        @computer.drive1541&.flush
        @stream&.close
        @gamepads.close
        @window.close
        report @computer.cpu.inspect
      end

      private

      def handle_events
        while (event = SDL.poll_event)
          case event
          when SDL::Quit
            @running = false
          when SDL::KeyDown
            handle_key_down(event)
          when SDL::KeyUp
            handle_key_up(event)
          when SDL::MouseMotion
            @pot_device&.move(event.xrel, event.yrel)
          when SDL::MouseButton
            handle_mouse_button(event)
          when SDL::ControllerDevice
            @gamepads.rescan
          end
        end
      end

      def handle_key_down(event)
        return host_key(event) if HOST_SYMS.include?(event.sym)

        port, dir = JoyMap.parse(event) if @mode == :joystick
        if port
          joystick(port).press(dir)
        else
          press_key(KeyMap.parse(event), event.repeat)
        end
      end

      # Tab, F10, F11 and F12 drive the front end, not the machine.
      def host_key(event)
        case event.sym
        when TOGGLE_SYM then cycle_mode(event.mod.anybits?(REVERSE_MOD) ? -1 : 1)
        when MUTE_SYM then toggle_mute
        when SAVE_SYM then @snapshots.save(@computer) unless event.repeat
        else restore_snapshot unless event.repeat
        end
      end

      # RESTORE isn't in the key matrix, so it goes to the machine instead,
      # once per press as the real key's one-shot fires.
      def press_key(key, repeat)
        return @computer.press_restore if key == :restore && !repeat
        return if key == :restore

        @computer.keyboard.press(key)
      end

      def handle_key_up(event)
        return if HOST_SYMS.include?(event.sym)

        port, dir = JoyMap.parse(event) if @mode == :joystick
        if port
          joystick(port).release(dir)
        else
          @computer.keyboard.release(KeyMap.parse(event))
        end
      end

      def handle_mouse_button(event)
        button = MOUSE_BUTTONS[event.button]
        return unless button && @pot_device

        if event.pressed
          @pot_device.press(button)
        else
          @pot_device.release(button)
        end
      end

      def joystick(port)
        port == 1 ? @computer.joystick1 : @computer.joystick2
      end

      def cycle_mode(step)
        modes = MODES.keys
        @mode = modes[(modes.index(@mode) + step) % modes.size]
        release_inputs
        attach_pot_device
        update_title
      end

      def toggle_mute
        return unless @stream

        @stream.toggle_mute
        update_title
      end

      # Runs the restored machine in place of the one before: the screen,
      # the drive LED, the gamepads and the sound go over to it. The input
      # mode stays the host's, so a mouse or paddles go back in their port.
      def restore_snapshot
        computer = @snapshots.restore
        return unless computer

        release_inputs
        @computer = computer
        @panes = panes
        @gamepads.computer = computer
        @stream&.sid = computer.sid
        attach_pot_device if POT_DEVICES.key?(@mode)
      end

      # The screen, and the drive LED in its border when a true drive is
      # plugged in.
      def panes
        screen = ScreenPane.new(@computer)
        drive = @computer.drive1541
        drive ? [screen, DriveLedPane.new(drive, screen)] : [screen]
      end

      def update_title
        tags = [MODES[@mode], @stream&.muted? && "MUTED"].select(&:itself)
        @window.title = [TITLE, *tags.map { |tag| "[#{tag}]" }].join(" ")
      end

      def open_stream
        sink = Audio::SDLSink.new(rate: Audio::Renderer::DEFAULT_RATE)
        report "Sound at #{sink.rate} Hz, F10 mutes"
        Audio::Stream.new(sink, @computer.sid,
                          on_underrun: -> { puts "Running below real time, so the sound will stutter." })
      rescue Audio::SDLSink::Error => e
        warn "badline: no sound, can't open the audio device: #{e.message}"
      end

      def fit_frame
        rate = @window.refresh_rate
        clock_hz = @computer.region.clock_hz
        @cycles_per_frame = clock_hz / rate
        @frame_seconds = @cycles_per_frame.fdiv(clock_hz)
        report "Display #{rate} Hz -> #{@cycles_per_frame} cycles/frame"
      end

      def report(line)
        puts line if @verbose
      end

      def attach_pot_device
        device_class, port = POT_DEVICES[@mode]
        @pot_device = device_class&.new
        ports = @computer.control_ports
        ports.device1 = port == 1 ? @pot_device : nil
        ports.device2 = port == 2 ? @pot_device : nil
        SDL::SetRelativeMouseMode.call(@pot_device ? 1 : 0)
      end

      def release_inputs
        SHARED_KEYS.each { |key| @computer.keyboard.release(key) }
        Joystick::DIRECTIONS.each_key do |dir|
          @computer.joystick1.release(dir)
          @computer.joystick2.release(dir)
        end
      end

      def canvas_width
        @panes.map { |pane| pane.left + pane.width }.max
      end

      def canvas_height
        @panes.map { |pane| pane.top + pane.height }.max
      end
    end
  end
end
