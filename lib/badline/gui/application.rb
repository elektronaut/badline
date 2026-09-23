# frozen_string_literal: true

module Badline
  module GUI
    class Application
      PAL_CLOCK_HZ = 985_248
      TITLE = "Badline"
      TOGGLE_SYM = SDL2::Key::TAB
      REVERSE_MOD = SDL2::Key::Mod::SHIFT

      SHARED_KEYS = %i[up left cursor_h cursor_v space w a s d lshift].freeze

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

      def initialize(media_path: nil, autostart: true, song: nil, sid_model: nil)
        @computer = Computer.new(sid_model: sid_model || Media.sid_model(media_path))
        puts Media.attach(@computer, media_path, autostart:, song:) if media_path

        @mode = :keyboard
        @pot_device = nil
        @panes = [ScreenPane.new(@computer)]
        @window = Window.new(
          title: TITLE,
          width: canvas_width, height: canvas_height,
          vsync: ENV["NOVSYNC"].nil?
        )
        @gamepads = Gamepads.new(@computer)
        @gamepads.names.each { |name| puts "Gamepad: #{name}" }

        rate = @window.refresh_rate
        @cycles_per_frame = PAL_CLOCK_HZ / rate
        puts "Display #{rate} Hz -> #{@cycles_per_frame} cycles/frame"
      end

      def run
        @running = true
        while @running
          handle_events
          @gamepads.poll
          @cycles_per_frame.times { @computer.cycle! }
          @window.draw(@panes)
        end
      ensure
        @gamepads.close
        puts @computer.cpu.inspect
      end

      private

      def handle_events
        while (event = SDL2::Event.poll)
          case event
          when SDL2::Event::Quit
            @running = false
          when SDL2::Event::KeyDown
            handle_key_down(event)
          when SDL2::Event::KeyUp
            handle_key_up(event)
          when SDL2::Event::MouseMotion
            @pot_device&.move(event.xrel, event.yrel)
          when SDL2::Event::MouseButton
            handle_mouse_button(event)
          when SDL2::Event::ControllerDevice
            @gamepads.rescan
          end
        end
      end

      def handle_key_down(event)
        return cycle_mode(event.mod.anybits?(REVERSE_MOD) ? -1 : 1) if event.sym == TOGGLE_SYM

        port, dir = JoyMap.parse(event) if @mode == :joystick
        if port
          joystick(port).press(dir)
        else
          @computer.keyboard.press(KeyMap.parse(event))
        end
      end

      def handle_key_up(event)
        return if event.sym == TOGGLE_SYM

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

        case event
        when SDL2::Event::MouseButtonDown then @pot_device.press(button)
        when SDL2::Event::MouseButtonUp then @pot_device.release(button)
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
        @window.title = [TITLE, MODES[@mode] && "[#{MODES[@mode]}]"].compact.join(" ")
      end

      def attach_pot_device
        device_class, port = POT_DEVICES[@mode]
        @pot_device = device_class&.new
        ports = @computer.control_ports
        ports.device1 = port == 1 ? @pot_device : nil
        ports.device2 = port == 2 ? @pot_device : nil
        SDL2::Mouse.relative_mode = !@pot_device.nil?
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
