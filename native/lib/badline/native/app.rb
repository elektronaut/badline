# frozen_string_literal: true

module Badline
  module Native
    # Opens the window, then runs the machine a frame at a time: poll
    # events, clock the frame's cycles, queue the SID's samples, upload the
    # changed lines, present and wait. Pacer decides the cycles and the wait.
    class App
      SCALE = 2
      TITLE = "Badline"
      STAGES = %w[events emulate audio blit present wait].freeze

      # Takes the frame limit, the pacing, the screenshot path and the sound
      # from Options.
      def initialize(computer, options)
        @computer = computer
        @frame_limit = options.frames
        @pacer = Pacer.new(paced: options.paced?, vsync: options.vsync?)
        @screenshot = options.screenshot
        @screen = Screen.new(computer.vic)
        drive = computer.drive1541
        @led = drive.nil? ? nil : DriveLed.new(drive)
        @controls = Controls.new(computer)
        @spent = Array.new(STAGES.size, 0.0)
        @slowest = 0.0
        open_window
        @sound = Sound.new(computer.sid, options.sound?)
        @gamepads = Gamepads.new(computer)
      end

      def run
        @frames = 0
        @running = true
        @started = @reported = now
        @pacer.start(@started)
        @reported_samples = 0
        frame while @running
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
        STAGES.size.times { |stage| @spent[stage] += stamps[stage + 1] - stamps[stage] }
        took = stamps[-2] - stamps.first
        @slowest = took if took > @slowest
        @frames += 1
        @running = false if @frames == @frame_limit
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
        SDL.rect_w(SDL.rect, Screen::WIDTH)
        SDL.rect_h(SDL.rect, Screen::HEIGHT)
        DriveLed.place
      end

      def close_window
        SDL.SDL_DestroyTexture(@texture)
        SDL.SDL_DestroyRenderer(@renderer)
        SDL.SDL_DestroyWindow(@window)
        SDL.SDL_Quit
      end

      def handle_events
        handle_event(SDL.event_type(SDL.event)) while SDL.SDL_PollEvent(SDL.event) != 0
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
        end
      end

      def handle_key(scancode, down)
        if [Keys::TAB, Keys::F9, Keys::F10].include?(scancode)
          handle_toggle(scancode) if down
        else
          @controls.key(scancode, down)
        end
      end

      def handle_toggle(scancode)
        if scancode == Keys::TAB
          @controls.cycle_mode(SDL.event_mod(SDL.event).anybits?(SDL::KMOD_SHIFT) ? -1 : 1)
          SDL.SDL_SetRelativeMouseMode(@controls.pot_device? ? 1 : 0)
        elsif scancode == Keys::F9
          @controls.swap_ports
        else
          @sound.toggle_mute
        end
        update_title
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
        SDL.SDL_UpdateTexture(@texture, SDL.rect, @screen.pixels, Screen::ROW_BYTES)
      end

      def draw
        SDL.SDL_RenderClear(@renderer)
        SDL.SDL_RenderCopy(@renderer, @texture, SDL.rect, SDL.rect)
        @led&.draw(@renderer)
        write_screenshot if @screenshot != "" && @frames + 1 == @frame_limit
        SDL.SDL_RenderPresent(@renderer)
      end

      def report(at)
        @pacer.check(50, at - @reported, at)
        @pacer.measure(50, at - @reported)
        fps = 50 / (at - @reported)
        stages = STAGES.each_with_index.map { |name, stage| "#{name} #{(@spent[stage] * 20).round(2)}" }
        puts "#{fps.round(1)} fps, per frame ms: #{stages.join(' ')}, slowest work #{(@slowest * 1000).round(2)}"
        report_sound(at) if @sound.on?
        @spent = Array.new(STAGES.size, 0.0)
        @slowest = 0.0
        @reported = at
      end

      def report_sound(at)
        sound = @sound
        rate = (sound.queued - @reported_samples) / (at - @reported)
        queue = sound.high.zero? ? "empty" : "#{(sound.low * 1000).round(1)}-#{(sound.high * 1000).round(1)} ms"
        puts "  sound #{rate.round} samples/s, queue #{queue}, #{sound.underruns} underruns, #{sound.dropped} dropped"
        sound.reset_levels
        @reported_samples = sound.queued
      end

      # Reads back what the renderer drew, before it is presented, and saves
      # it as a BMP.
      def write_screenshot
        SDL.SDL_GetRendererOutputSize(@renderer, SDL.output_w, SDL.output_h)
        width = SDL.read_i32(SDL.output_w)
        height = SDL.read_i32(SDL.output_h)
        data = LibC.malloc(width * height * 4)
        SDL.SDL_RenderReadPixels(@renderer, nil, SDL::PIXELFORMAT_RGB888, data, width * 4)
        surface = SDL.SDL_CreateRGBSurfaceWithFormatFrom(data, width, height, 32, width * 4, SDL::PIXELFORMAT_RGB888)
        SDL.SDL_SaveBMP_RW(surface, SDL.SDL_RWFromFile(@screenshot, "wb"), 1)
        SDL.SDL_FreeSurface(surface)
        LibC.free(data)
        puts "wrote #{@screenshot}, #{width}x#{height}"
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
