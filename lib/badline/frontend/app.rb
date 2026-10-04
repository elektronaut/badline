# frozen_string_literal: true

module Badline
  module Frontend
    # Opens the window, then runs the machine a frame at a time: poll
    # events, clock the frame's cycles, queue the SID's samples, upload the
    # changed lines, present and wait. Pacer decides the cycles and the wait.
    class App
      SCALE = 2
      DROPFILE = 0x1000
      TITLE = "Badline"

      # Takes the frame limit, the pacing, the snapshot path, the sound and
      # the verbosity from Options, and runs the timeline's events.
      def initialize(computer, options, timeline)
        @computer = computer
        @frame_limit = options.frames
        @verbose = options.verbose?
        @pacer = Pacer.new(paced: options.paced?, vsync: options.vsync?, verbose: @verbose, region: computer.region)
        @timeline = timeline
        @snapshots = Snapshots.new(computer, options)
        @screen = Screen.new(computer.vic)
        @led = DriveLed.for(computer)
        @controls = Controls.new(computer)
        open_window
        @sound = Sound.new(computer.sid, computer.region.clock_hz, options.sound?, @verbose)
        @gamepads = Gamepads.new(computer, @verbose)
        @frame_report = FrameReport.new(@sound)
        @menu = PauseMenu.new(Painter.new(@renderer), options, @snapshots)
      end

      def run
        @frames = 0
        @running = true
        @started = @reported = now
        @pacer.start(@started)
        @menu.open? ? paused_frame : frame while @running
        @snapshots.finish
        @computer.drive1541&.flush
        @gamepads.close
        @sound.close
        close_window
      end

      private

      def frame
        stamps = [now]
        handle_events
        @gamepads.poll
        stamps << now
        emulate
        stamps << now
        @sound.feed
        stamps << now
        upload
        stamps << now
        draw
        stamps << now
        @pacer.wait(@sound)
        stamps << now
        finish_frame(stamps)
      end

      def finish_frame(stamps)
        @frame_report.add(stamps) if @verbose
        @frames += 1
        @timeline.run(@computer, @frames)
        @snapshots.tick(@frames)
        @running = false if @frames == @frame_limit || @timeline.quit?(@frames)
        @pacer.check(Pacer::EARLY_CHECK, stamps.last - @started, stamps.last) if @frames == Pacer::EARLY_CHECK
        report(stamps.last) if (@frames % 50).zero?
      end

      def open_window
        abort "SDL_Init: #{SDL.SDL_GetError}" unless SDL.SDL_Init(SDL::INIT_VIDEO | SDL::INIT_EVENTS).zero?

        SDL.SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0")
        SDL.SDL_SetHint("SDL_MOUSE_RELATIVE_SCALING", "0")
        @window = SDL.SDL_CreateWindow(
          TITLE, SDL::WINDOWPOS_CENTERED, SDL::WINDOWPOS_CENTERED,
          Screen::WIDTH * SCALE, Screen::HEIGHT * SCALE, SDL::WINDOW_RESIZABLE
        )
        flags = SDL::RENDERER_ACCELERATED
        flags |= SDL::RENDERER_PRESENTVSYNC if @pacer.vsync?
        @renderer = SDL.SDL_CreateRenderer(@window, -1, flags)
        fit_display if @pacer.vsync?
        SDL.SDL_RenderSetLogicalSize(@renderer, Screen::WIDTH, Screen::HEIGHT)
        create_texture
      end

      def create_texture
        @texture = SDL.SDL_CreateTexture(
          @renderer, SDL::PIXELFORMAT_RGB888, SDL::TEXTUREACCESS_STREAMING, Screen::WIDTH, Screen::HEIGHT
        )
      end

      def close_window
        SDL.SDL_DestroyTexture(@texture)
        SDL.SDL_DestroyRenderer(@renderer)
        SDL.SDL_DestroyWindow(@window)
        SDL.SDL_Quit
      end

      def handle_events
        handle_event(SDL.event_type(SDL.event)) while !@menu.open? && SDL.SDL_PollEvent(SDL.event) != 0
      end

      def handle_event(type)
        case type
        when SDL::QUIT
          @running = false
        when SDL::KEYDOWN, SDL::KEYUP
          handle_key(SDL.event_scancode(SDL.event), type == SDL::KEYDOWN) if SDL.event_repeat(SDL.event).zero?
        when SDL::MOUSEMOTION
          @controls.mouse_motion(SDL.event_xrel(SDL.event), SDL.event_yrel(SDL.event))
        when SDL::MOUSEBUTTONDOWN, SDL::MOUSEBUTTONUP
          @controls.mouse_button(SDL.event_button(SDL.event), type == SDL::MOUSEBUTTONDOWN)
        when SDL::CONTROLLERDEVICEADDED, SDL::CONTROLLERDEVICEREMOVED
          @gamepads.rescan
        when DROPFILE then resume(false) unless @menu.drop(@computer, @controls, @sound)
        end
      end

      def handle_key(scancode, down)
        if [Keys::TAB, Keys::F9, Keys::F10].include?(scancode)
          handle_toggle(scancode) if down
        elsif down && @snapshots.key(scancode)
          swap(@snapshots.computer)
        elsif !Snapshots::KEYS.include?(scancode)
          @controls.key(scancode, down)
        end
      end

      # Runs the restored machine in place of the one before: the screen,
      # the drive LED, the controls, the gamepads and the sound go over to
      # it.
      def swap(computer)
        @computer = computer
        @screen = Screen.new(computer.vic)
        @led = DriveLed.for(computer)
        @controls.computer = computer
        @gamepads.computer = computer
        @sound.switch(computer.sid, computer.region.clock_hz)
        @snapshots.computer = computer
      end

      def handle_toggle(scancode)
        if scancode == Keys::TAB
          @controls.toggle_keys
        elsif scancode == Keys::F9
          return open_menu
        else
          @sound.toggle_mute
        end
        update_title
      end

      def open_menu = @menu.show(@computer, @controls, @sound)

      # Closes the menu and runs the machine on from where it stood,
      # pressing the cartridge's freeze button if asked.
      def resume(freeze)
        @menu.close
        SDL.SDL_SetRelativeMouseMode(@controls.pot_device? ? 1 : 0)
        @timeline.press_freeze(@computer, @frames) if freeze
        @reported = now
        @pacer.start(@reported)
        update_title
      end

      # Runs a frame of the menu, which has the keys and the mouse while the
      # machine stands still.
      def paused_frame
        action = @menu.frame(@renderer, @texture, @controls)
        if action == :quit
          @running = false
        elsif !action.nil?
          swap(@menu.computer) if action == :swap
          resume(action == :freeze)
        end
      end

      def update_title
        title = TITLE
        title += " [#{@controls.tag}]" unless @controls.tag.empty?
        title += " [MUTED]" if @sound.muted?
        SDL.SDL_SetWindowTitle(@window, title)
      end

      def fit_display
        SDL.SDL_GetWindowDisplayMode(@window, SDL.display_mode)
        @pacer.fit(SDL.mode_refresh(SDL.display_mode))
      end

      def emulate
        computer = @computer
        cycles = @pacer.cycles(@sound)
        i = 0
        while i < cycles
          computer.cycle!
          i += 1
        end
      end

      def upload
        @screen.update
        SDL.SDL_UpdateTexture(@texture, nil, @screen.pixels, Screen::ROW_BYTES)
      end

      def draw
        SDL.SDL_RenderClear(@renderer)
        SDL.SDL_RenderCopy(@renderer, @texture, nil, nil)
        @led&.draw(@renderer)
        @timeline.screenshots(@frames + 1).each { |path| Screenshot.write(@renderer, path) }
        SDL.SDL_RenderPresent(@renderer)
      end

      def report(at)
        @pacer.check(50, at - @reported, at)
        @pacer.measure(50, at - @reported)
        @frame_report.show(at - @reported) if @verbose
        @reported = at
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
