# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's window, which `sid` plays in. A header with the
    # tune, the views and the SID model (PlayerHeader), and a footer with
    # the time and the buttons that step through the queue (PlayerFooter),
    # frame one of two views: the visualizer, with each voice's note and
    # output and the mix, and the SID view, with everything the chip is
    # doing. The window's height follows the view.
    #
    # It stands in for the terminal, so Audio::Jukebox drives it the same
    # way: #wait handles the window's clicks and keys between frames and
    # redraws it at the display's pace. The SID model buttons switch the
    # chip playing on the spot, and each tune after it starts on the same
    # choice.
    class PlayerWindow < Audio::Terminal
      WIDTH = PlayerHeader::WIDTH
      HEADER = 52
      SCALE = 2
      TITLE = "Badline"
      FRAME = 1.0 / 50

      DROPFILE = 0x1000

      BACKGROUND = Screen::COLORS[6]
      WARNING = Screen::COLORS[10]

      CHIPS = PlayerHeader::CHIPS

      KEYS = {
        17 => :next, 19 => :previous,
        79 => :next_subtune, 80 => :previous_subtune,
        44 => :pause, 22 => :shuffle, 15 => :loop, 4 => :all_subtunes,
        20 => :quit, 41 => :quit,
        54 => :back, 55 => :forward,
        43 => :view, 6 => :chip
      }.freeze

      def initialize(input:, output:)
        super
        @window = nil
        @renderer = nil
        @painter = nil
        @buttons = nil
        @player = nil
        @tune_file = nil
        @history = SIDHistory.new(Audio::Renderer::DEFAULT_RATE)
        @state = PlayerState.new
        @commands = PlayerCommands.new(@state)
        @own_model = :mos6581
        @next_draw = 0.0
        @seek_to = 0.0
        @dropped = []
      end

      attr_reader :seek_to

      # The files dropped on the window since it last said :drop.
      def dropped
        paths = @dropped
        @dropped = []
        paths
      end

      def session
        open_window
        yield
      ensure
        close_window
      end

      # Handles the window's clicks and keys and redraws it until `seconds`
      # are up, returning early with those that ask the jukebox for
      # something.
      def wait(seconds)
        actions = poll
        deadline = now + seconds
        loop do
          draw if now >= @next_draw
          left = deadline - now
          break if left <= 0 || !actions.empty?

          SDL.SDL_Delay([([left, @next_draw - now].min * 1000).floor, 1].max)
          actions.concat(poll)
        end
        actions
      end

      def header(lines) = lines

      def announce(lines) = lines

      def place(tune, tunes)
        @state.tune = tune
        @state.tunes = tunes
      end

      def status(subtune:, subtunes:, elapsed:, length:, notes: [])
        state = @state
        state.subtune = subtune
        state.subtunes = subtunes
        state.elapsed = elapsed
        state.length = length
        state.notes = notes
      end

      # Follows the renderer's SID from here on, on the model chosen.
      def playing(renderer)
        @player = renderer.player
        @tune_file = renderer.tune
        @history = SIDHistory.new(renderer.rate)
        sid = @player.sid
        sid.record_voices!
        @own_model = sid.model
        renderer.observer = ->(samples, rendered) { @history.record(sid, samples, rendered) }
        choose_model
        name = renderer.tune.name
        SDL.SDL_SetWindowTitle(@window, name.empty? ? TITLE : "#{name} - #{TITLE}") unless @window.nil?
      end

      private

      def height = HEADER + body_height + PlayerFooter::HEIGHT

      def body_height = @state.view.zero? ? VisualizerView::HEIGHT : SIDView::HEIGHT

      def open_window
        SDL.SDL_InitSubSystem(SDL::INIT_VIDEO | SDL::INIT_EVENTS)
        SDL.SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0")
        @window = SDL.SDL_CreateWindow(TITLE, SDL::WINDOWPOS_CENTERED, SDL::WINDOWPOS_CENTERED,
                                       WIDTH * SCALE, height * SCALE, SDL::WINDOW_RESIZABLE)
        @renderer = SDL.SDL_CreateRenderer(@window, -1, SDL::RENDERER_ACCELERATED)
        SDL.SDL_RenderSetLogicalSize(@renderer, WIDTH, height)
        @painter = Painter.new(@renderer)
        @buttons = Buttons.new(@painter)
        @top = PlayerHeader.new(@painter, @buttons)
        @bottom = PlayerFooter.new(@painter, @buttons)
        @visualizer = VisualizerView.new(@painter, HEADER + 4)
        @sid_view = SIDView.new(@painter, HEADER + 4)
      end

      def close_window
        return if @window.nil?

        @painter&.close
        SDL.SDL_DestroyRenderer(@renderer)
        SDL.SDL_DestroyWindow(@window)
        SDL.SDL_QuitSubSystem(SDL::INIT_VIDEO | SDL::INIT_EVENTS)
        @window = nil
      end

      def poll
        actions = []
        while SDL.SDL_PollEvent(SDL.event) != 0
          case SDL.event_type(SDL.event)
          when SDL::QUIT then actions << :quit
          when SDL::KEYDOWN then key(SDL.event_scancode(SDL.event), actions) if SDL.event_repeat(SDL.event).zero?
          when SDL::MOUSEMOTION then @buttons&.point(SDL.event_x(SDL.event), SDL.event_y(SDL.event))
          when SDL::MOUSEBUTTONDOWN then click(actions) if SDL.event_button(SDL.event) == 1
          when DROPFILE then drop(actions)
          end
        end
        actions
      end

      def drop(actions)
        file = SDL.event_file(SDL.event)
        @dropped << LibC.strstr(file, "")
        LibC.free(file)
        actions << :drop unless actions.include?(:drop)
      end

      def key(scancode, actions)
        action = KEYS[scancode]
        command(action, actions) unless action.nil?
      end

      def click(actions)
        return if @buttons.nil?

        left = SDL.event_x(SDL.event)
        action = @buttons.action_at(left, SDL.event_y(SDL.event))
        return if action.nil?

        @seek_to = PlayerFooter.seek(left, @state.length) if action == :seek
        command(action, actions)
      end

      # Lets PlayerCommands handle the action, then follows a change of view
      # or SID model it made.
      def command(action, actions)
        view = @state.view
        chip = @state.chip
        passed = @commands.handle(action)
        actions << passed unless passed.nil?
        resize unless view == @state.view
        choose_model unless chip == @state.chip
      end

      def resize
        SDL.SDL_SetWindowSize(@window, WIDTH * SCALE, height * SCALE)
        SDL.SDL_RenderSetLogicalSize(@renderer, WIDTH, height)
        @next_draw = 0.0
      end

      def choose_model
        return if @player.nil?

        chip = CHIPS[@state.chip]
        model = chip == :auto ? @own_model : chip
        sid = @player.sid
        sid.model = model unless sid.model == model
      end

      def draw
        @next_draw = now + FRAME
        return if @renderer.nil?

        SDL.SDL_SetRenderDrawColor(@renderer, (BACKGROUND >> 16) & 0xff, (BACKGROUND >> 8) & 0xff,
                                   BACKGROUND & 0xff, 255)
        SDL.SDL_RenderClear(@renderer)
        @buttons.forget
        @top.draw(@state, @tune_file, @player.nil? ? :none : @player.sid.model)
        draw_body
        @bottom.draw(@state, height - PlayerFooter::HEIGHT)
        SDL.SDL_RenderPresent(@renderer)
      end

      def draw_body
        return draw_empty if @player.nil?

        played = @state.played
        if @state.view.zero?
          @visualizer.draw(@history, played, clock_hz: @player.clock_hz)
        else
          @sid_view.draw(@history, played, clock_hz: @player.clock_hz, model: @player.sid.model)
        end
      end

      def draw_empty
        hint = "Drop .sid files or folders here"
        @painter.text((WIDTH - Painter.width(hint, scale: 2)) / 2, HEADER + (body_height / 2) - 8, hint,
                      SIDView::TEXT, scale: 2)
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
