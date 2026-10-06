# frozen_string_literal: true

module Badline
  module Frontend
    # Opens the window, then runs the machine a frame at a time: poll
    # events, clock the frame's cycles, queue the sound's samples, upload the
    # changed lines, present and wait. Pacer decides the cycles and the wait.
    class App
      DROPFILE = 0x1000

      # Takes the frame limit, the pacing, the snapshot path, the sound and
      # the verbosity from Options, and runs the timeline's events.
      def initialize(computer, options, timeline)
        @computer = computer
        @frame_limit = options.frames
        @verbose = options.verbose?
        timing = computer.timing
        @pacer = Pacer.new(paced: options.paced?, vsync: options.vsync?, verbose: @verbose, timing:)
        @timeline = timeline
        @snapshots = Snapshots.new(computer, options)
        @screen = Screen.new(computer.video, timing.crop)
        @led = DriveLed.for(computer)
        @controls = Controls.new(computer)
        @window = MachineWindow.new(@screen, timing.pixel_width, vsync: @pacer.vsync?)
        @pacer.fit(@window.refresh_rate) if @pacer.vsync?
        @sound = Sound.new(computer.sound_source, timing.clock_hz, options.sound?, @verbose)
        @gamepads = Gamepads.new(computer, @verbose)
        @frame_report = FrameReport.new(@sound)
        @menu = PauseMenu.new(Painter.new(@window.renderer), options, @snapshots)
        @menu.center(@window.width, @window.height)
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
        @window.close
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
        timing = computer.timing
        @screen = Screen.new(computer.video, timing.crop)
        @window.fit(@screen, timing.pixel_width)
        @menu.center(@window.width, @window.height)
        @led = DriveLed.for(computer)
        @controls.computer = computer
        @gamepads.computer = computer
        @sound.switch(computer.sound_source, timing.clock_hz)
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
        action = @menu.frame(@window.renderer, @window.texture, @controls)
        if action == :quit
          @running = false
        elsif !action.nil?
          swap(@menu.computer) if action == :swap
          resume(action == :freeze)
        end
      end

      def update_title
        tags = []
        tags << @controls.tag unless @controls.tag.empty?
        tags << "MUTED" if @sound.muted?
        @window.title(tags)
      end

      def emulate
        @computer.run_cycles(@pacer.cycles(@sound))
      end

      def upload
        @screen.update
        @window.upload(@screen)
      end

      def draw
        renderer = @window.renderer
        SDL.SDL_RenderClear(renderer)
        SDL.SDL_RenderCopy(renderer, @window.texture, nil, nil)
        @led&.draw(renderer, @window.width, @window.height)
        @timeline.screenshots(@frames + 1).each { |path| Screenshot.write(renderer, path) }
        SDL.SDL_RenderPresent(renderer)
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
