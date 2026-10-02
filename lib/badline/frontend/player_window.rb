# frozen_string_literal: true

module Badline
  module Frontend
    # The SID player's window, which `sid` plays in, drawn by PlayerScreen:
    # a header with the tune, its STIL credit, the views and the SID model,
    # and a footer with the time and the buttons that step through the
    # queue, framing one of three views: the visualizer, with each voice's
    # note and output and the mix, the SID view, with everything the chip
    # is doing, and the tune's STIL entry. The window's height follows the
    # view, and .sid files and folders dropped on it join the queue.
    #
    # It stands in for the terminal, so Audio::Jukebox drives it the same
    # way: #wait handles the window's clicks, keys and drops between frames
    # and redraws it at the display's pace. The SID model buttons switch
    # the chips playing on the spot, and each tune after it starts on the
    # same choice. AUTO gives each of a tune's SIDs its own model.
    class PlayerWindow < Audio::Terminal
      FRAME = 1.0 / 50

      MOUSEWHEEL = 0x403
      DROPFILE = 0x1000
      UP = 82
      DOWN = 81

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
        @screen = PlayerScreen.new
        @player = nil
        @tune_file = nil
        @history = SIDHistory.new(Audio::Renderer::DEFAULT_RATE)
        @state = PlayerState.new
        @commands = PlayerCommands.new(@state)
        @next_draw = 0.0
        @seek_to = 0.0
        @dropped = []
        @credits = []
        @stil = []
        @stil_subtune = 0
        @subtune_stil = []
        @scrolling = false
      end

      attr_reader :seek_to

      # The files dropped on the window since it last said :drop.
      def dropped
        paths = @dropped
        @dropped = []
        paths
      end

      def session
        @screen.open(@state.view)
        @screen.info.show(@stil, @stil_subtune, @subtune_stil)
        yield
      ensure
        @screen.close
      end

      # Handles the window's clicks, keys and drops and redraws it until
      # `seconds` are up, returning early with those that ask the jukebox
      # for something.
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

      # Keeps the subtune's STIL credits for the header and the whole entry
      # for the INFO view.
      def stil(fields, subtune, subtune_fields)
        @credits = Storage::STIL::Credit.list(subtune_fields.empty? ? fields : subtune_fields)
        @stil = fields
        @stil_subtune = subtune
        @subtune_stil = subtune_fields
        @screen.info.show(fields, subtune, subtune_fields) if @screen.open?
      end

      # Follows the renderer's SIDs from here on, on the model chosen.
      def playing(renderer)
        @player = renderer.player
        @tune_file = renderer.tune
        stereo = @player.stereo
        @history = SIDHistory.new(renderer.rate, stereo.sids.size)
        stereo.sids.each(&:record_voices!)
        renderer.observer = ->(samples, rendered) { @history.record(stereo.sids, stereo.outputs, samples, rendered) }
        choose_model
        @screen.title(renderer.tune.name)
      end

      private

      def poll
        actions = []
        while SDL.SDL_PollEvent(SDL.event) != 0
          case SDL.event_type(SDL.event)
          when SDL::QUIT then actions << :quit
          when SDL::KEYDOWN then key(SDL.event_scancode(SDL.event), actions) if SDL.event_repeat(SDL.event).zero?
          when SDL::MOUSEMOTION then point
          when SDL::MOUSEBUTTONDOWN then click(actions) if SDL.event_button(SDL.event) == 1
          when SDL::MOUSEBUTTONUP then @scrolling = false
          when MOUSEWHEEL then @screen.info.scroll(-3 * SDL.event_x(SDL.event))
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

      def point
        top = SDL.event_y(SDL.event)
        @screen.buttons.point(SDL.event_x(SDL.event), top)
        @screen.info.scroll_along(top) if @scrolling
      end

      def key(scancode, actions)
        return @screen.info.scroll(scancode == UP ? -1 : 1) if [UP, DOWN].include?(scancode)

        action = KEYS[scancode]
        command(action, actions) unless action.nil?
      end

      def click(actions)
        left = SDL.event_x(SDL.event)
        action = @screen.buttons.action_at(left, SDL.event_y(SDL.event))
        return if action.nil?

        @seek_to = PlayerFooter.seek(left, @state.length) if action == :seek
        return scroll_along if action == :scroll

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

      def scroll_along
        @scrolling = true
        @screen.info.scroll_along(SDL.event_y(SDL.event))
      end

      def resize
        @screen.resize(@state.view)
        @next_draw = 0.0
      end

      def choose_model
        return if @player.nil?

        @player.stereo.refit(CHIPS[@state.chip])
      end

      def draw
        @next_draw = now + FRAME
        @screen.draw(@state, @player, @history, @tune_file, Storage::STIL::Credit.at(@credits, @state.played))
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
