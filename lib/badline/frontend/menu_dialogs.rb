# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's screens that take over its panel: the file browser
    # INSERT and Quick open bring up, and the question before a cartridge
    # or Quick open power cycles the machine. A disk or tape picked goes
    # straight in.
    class MenuDialogs
      EXTENSIONS = {
        disk: %w[.d64 .d71 .d81 .g64 .t64 .m3u .vfl], tape: %w[.tap], cartridge: %w[.crt],
        program: %w[.d64 .d71 .d81 .g64 .t64 .m3u .vfl .tap .crt .prg .p00 .sid]
      }.freeze
      TITLES = { disk: "INSERT A DISK", tape: "INSERT A TAPE", cartridge: "INSERT A CARTRIDGE",
                 program: "QUICK OPEN" }.freeze

      ESCAPE = 41
      RETURN = 40
      SPACE = 44

      # The machine Quick open started.
      attr_reader :computer

      def initialize(painter, buttons, media, options)
        media_path = options.media_path.to_s
        @buttons = buttons
        @media = media
        @options = options
        @browser = FileBrowser.new(painter, buttons)
        @confirmation = Confirmation.new(painter, buttons)
        @browsing = nil
        @browse_from = media_path.empty? ? Dir.pwd : File.dirname(File.expand_path(media_path))
        @computer = nil
      end

      def open? = !@browsing.nil? || @confirmation.open?

      # Opens the browser on the files for `kind`: :disk, :tape, :cartridge
      # or :program.
      def browse(kind)
        @browsing = kind
        @browser.open(@browse_from, EXTENSIONS.fetch(kind))
      end

      def ask_remove = @confirmation.ask(:remove, @media.cartridge_name)

      # Puts a dropped disk or tape in its device, or asks before a
      # cartridge or a program starts, and says whether it asks. Other
      # files are left alone.
      def drop(path)
        extension = File.extname(path).downcase
        return @media.insert(:disk, path) && false if EXTENSIONS[:disk].include?(extension)
        return @media.insert(:tape, path) && false if EXTENSIONS[:tape].include?(extension)
        return false unless EXTENSIONS[:program].include?(extension)

        @confirmation.ask(extension == ".crt" ? :cartridge : :start, path)
        true
      end

      # Handles a key, and returns :resume or :swap once a question is
      # answered yes, or nil.
      def key(scancode)
        return browsed(@browser.key(scancode)) unless @browsing.nil?
        return answer(:cancel) if scancode == ESCAPE
        return answer(@buttons.focus) if [RETURN, SPACE].include?(scancode)

        direction = PauseMenu::ARROWS[scancode]
        @buttons.shift(direction == :up ? -1 : 1, 1) if %i[up down].include?(direction)
        nil
      end

      # Handles a click on the browser's list at `top`, or on a question's
      # answer, `action`.
      def click(action, top) = action == :browse ? browsed(@browser.click(top)) : answer(action)

      def scroll(rows) = @browser.scroll(rows)

      def draw(left, top, width)
        return @browser.draw(left, top, width, TITLES.fetch(@browsing)) unless @browsing.nil?

        @confirmation.draw(left, top)
      end

      private

      # Puts the disk or tape picked in, or asks before a cartridge or
      # Quick open power cycles the machine, and leaves the browser, as Esc
      # does.
      def browsed(picked)
        return nil if picked.nil?

        kind = @browsing
        @browse_from = @browser.directory
        @browsing = nil
        return nil if picked == :cancel

        if %i[disk tape].include?(kind)
          @media.insert(kind, picked)
        else
          @confirmation.ask(kind == :cartridge ? :cartridge : :start, picked)
        end
        nil
      end

      # Does what the question asked about if `action` is :confirm, and
      # returns :resume, or :swap for a new machine.
      def answer(action)
        question = @confirmation.close
        return nil unless action == :confirm

        path = question[1]
        case question[0]
        when :cartridge then @media.attach_cartridge(path) ? :resume : nil
        when :remove then @media.remove_cartridge && :resume
        else
          @computer = @media.start(@options, path)
          @computer.nil? ? nil : :swap
        end
      end
    end
  end
end
