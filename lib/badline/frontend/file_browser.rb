# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's file browser, which lists a folder's subfolders and
    # the files a device takes, folders first, each by name. The keys move
    # through the list, open a folder or pick a file, go up a folder, and
    # jump to the next name starting with a letter or digit. A click picks
    # the row under it, and the wheel scrolls.
    class FileBrowser
      ROW = 12
      ROWS = 12
      COLUMNS = 40

      RETURN = 40
      ESCAPE = 41
      BACKSPACE = 42
      HOME = 74
      PAGE_UP = 75
      END_KEY = 77
      PAGE_DOWN = 78
      RIGHT = 79
      LEFT = 80
      DOWN = 81
      UP = 82
      DIGITS = "1234567890"

      attr_reader :directory

      def initialize(painter, buttons)
        @painter = painter
        @buttons = buttons
        @open = false
        @directory = Dir.pwd
        @extensions = []
        @names = []
        @folders = 0
        @selected = 0
        @top = 0
        @list_top = 0
      end

      def open? = @open

      # What a name sorts by: lower case, with its numbers padded, so disk 2
      # comes before disk 10.
      def self.order(name) = name.downcase.gsub(/\d+/) { |digits| digits.rjust(10, "0") }

      # Lists `directory` for the files with one of `extensions`.
      def open(directory, extensions)
        @open = true
        @extensions = extensions
        enter(directory)
      end

      def close
        @open = false
      end

      # Handles a key, and returns the path of a file picked, :cancel when
      # Esc leaves the browser, or nil.
      def key(scancode)
        return :cancel if scancode == ESCAPE
        return pick if [RETURN, RIGHT].include?(scancode)
        return up if [LEFT, BACKSPACE].include?(scancode)

        select(@selected + step(scancode)) unless step(scancode).zero?
        jump(scancode)
        nil
      end

      # Picks the row at `top`, as Return would.
      def click(top)
        row = (top - @list_top) / ROW
        return nil if row.negative? || @top + row >= @names.size

        @selected = @top + row
        pick
      end

      def scroll(rows)
        @top = (@top + rows).clamp(0, [@names.size - ROWS, 0].max)
      end

      def draw(left, top, width, title)
        @painter.text(left, top, title, PauseMenu::BRIGHT)
        @painter.text(left, top + ROW + 2, shown_directory, PauseMenu::DIM)
        @list_top = top + (ROW * 2) + 8
        @buttons.area([left, @list_top, width, ROW * ROWS], :browse)
        draw_rows(left, width)
        draw_bar(left + width - 2) if @names.size > ROWS
        @painter.text(left, @list_top + (ROW * ROWS) + 6, "RETURN: OPEN  LEFT: BACK  ESC: CANCEL",
                      PauseMenu::DIM)
      end

      private

      # The folder's path, cut at the start to fit.
      def shown_directory
        length = @directory.length
        length > COLUMNS ? "...#{@directory[length - COLUMNS + 3, COLUMNS - 3]}" : @directory
      end

      def draw_rows(left, width)
        ROWS.times do |row|
          index = @top + row
          break if index >= @names.size

          name = label(index)
          top = @list_top + (row * ROW)
          if index == @selected
            @painter.box(left - 2, top - 2, width - 4, ROW, PauseMenu::TEXT)
            @painter.text(left, top, name, PauseMenu::PANEL)
          else
            @painter.text(left, top, name, index < @folders ? PauseMenu::BRIGHT : PauseMenu::TEXT)
          end
        end
      end

      def draw_bar(left)
        height = ROW * ROWS
        size = [(height * ROWS) / @names.size, 4].max
        offset = ((height - size) * @top) / [@names.size - ROWS, 1].max
        @painter.box(left, @list_top - 2, 2, height, PauseMenu::EDGE)
        @painter.box(left, @list_top - 2 + offset, 2, size, PauseMenu::TEXT)
      end

      def label(index)
        name = @names[index]
        name += "/" if index < @folders
        Painter.fit(name, COLUMNS)
      end

      def step(scancode)
        case scancode
        when UP then -1
        when DOWN then 1
        when PAGE_UP then -ROWS
        when PAGE_DOWN then ROWS
        when HOME then -@names.size
        when END_KEY then @names.size
        else 0
        end
      end

      def select(index)
        return if @names.empty?

        @selected = index.clamp(0, @names.size - 1)
        @top = @selected if @selected < @top
        @top = @selected - ROWS + 1 if @selected >= @top + ROWS
      end

      # Selects the next name after the one selected that starts with the
      # key's letter or digit.
      def jump(scancode)
        char = if scancode.between?(4, 29) then (97 + scancode - 4).chr
               elsif scancode.between?(30, 39) then DIGITS[scancode - 30]
               else ""
               end
        return if char.empty? || @names.empty?

        @names.size.times do |offset|
          index = (@selected + 1 + offset) % @names.size
          next unless @names[index].downcase.start_with?(char)

          select(index)
          break
        end
      end

      def pick
        return nil if @names.empty?

        path = File.join(@directory, @names[@selected])
        return path unless @selected < @folders

        @names[@selected] == ".." ? up : enter(path)
      end

      def up
        parent = File.dirname(@directory)
        return nil if parent == @directory

        from = File.basename(@directory)
        enter(parent)
        index = @names.index(from)
        select(index) unless index.nil?
        nil
      end

      def enter(directory)
        @directory = File.expand_path(directory)
        folders = []
        files = []
        children(@directory).each do |name|
          next if name.start_with?(".")

          if File.directory?(File.join(@directory, name))
            folders << name
          elsif @extensions.include?(File.extname(name).downcase)
            files << name
          end
        end
        listing(folders, files)
        nil
      end

      def listing(folders, files)
        folders = folders.sort_by { |name| FileBrowser.order(name) }
        folders.unshift("..") unless File.dirname(@directory) == @directory
        @folders = folders.size
        @names = folders + files.sort_by { |name| FileBrowser.order(name) }
        @selected = 0
        @top = 0
      end

      def children(directory)
        Dir.children(directory)
      rescue SystemCallError
        []
      end
    end
  end
end
