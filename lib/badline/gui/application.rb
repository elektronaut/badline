# frozen_string_literal: true

module Badline
  module GUI
    class Application
      PAL_CLOCK_HZ = 985_248
      TITLE = "Badline"
      TOGGLE_SYM = SDL2::Key::TAB

      SHARED_KEYS = %i[up left cursor_h cursor_v space w a s d lshift].freeze

      def initialize(media_path: nil, autostart: true, debug: false)
        @computer = Computer.new(debug:)
        puts Media.attach(@computer, media_path, autostart:) if media_path

        @joystick_mode = false
        @panes = [ScreenPane.new(@computer)]
        @window = Window.new(
          title: TITLE,
          width: canvas_width, height: canvas_height,
          vsync: ENV["NOVSYNC"].nil?
        )

        rate = @window.refresh_rate
        @cycles_per_frame = PAL_CLOCK_HZ / rate
        puts "Display #{rate} Hz -> #{@cycles_per_frame} cycles/frame"
      end

      def run
        @running = true
        while @running
          handle_events
          @cycles_per_frame.times { @computer.cycle! }
          @window.draw(@panes)
        end
      ensure
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
          end
        end
      end

      def handle_key_down(event)
        return toggle_joystick_mode if event.sym == TOGGLE_SYM

        port, dir = JoyMap.parse(event) if @joystick_mode
        if port
          joystick(port).press(dir)
        else
          @computer.keyboard.press(KeyMap.parse(event))
        end
      end

      def handle_key_up(event)
        return if event.sym == TOGGLE_SYM

        port, dir = JoyMap.parse(event) if @joystick_mode
        if port
          joystick(port).release(dir)
        else
          @computer.keyboard.release(KeyMap.parse(event))
        end
      end

      def joystick(port)
        port == 1 ? @computer.joystick1 : @computer.joystick2
      end

      def toggle_joystick_mode
        @joystick_mode = !@joystick_mode
        if @joystick_mode
          SHARED_KEYS.each { |key| @computer.keyboard.release(key) }
        else
          release_joysticks
        end
        @window.title = @joystick_mode ? "#{TITLE} [JOY]" : TITLE
      end

      def release_joysticks
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
