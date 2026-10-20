# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's screens that take over its panel: the file browser
    # INSERT, Quick open and LOAD bring up, the question before a cartridge
    # or Quick open power cycles the machine, the prompt for a save's name,
    # and the list of a PET's or a CBM-II's drive types. A disk or tape
    # picked goes straight in, a save loads, and a drive type picked goes on
    # the bus.
    class MenuDialogs
      EXTENSIONS = {
        disk: Media::Extensions::DEVICE8, tape: Media::Extensions.of(%i[tape]),
        cartridge: Media::Extensions.of(%i[cartridge]), program: Media::Extensions::ALL, snapshot: %w[.vsf]
      }.freeze
      TITLES = { disk: "INSERT A DISK", tape: "INSERT A TAPE", cartridge: "INSERT A CARTRIDGE",
                 program: "QUICK OPEN", snapshot: "LOAD A SAVE" }.freeze

      # The machine Quick open started or a save loaded.
      attr_reader :computer

      def initialize(painter, buttons, media, options, snapshots)
        media_path = options.media_path.to_s
        @buttons = buttons
        @media = media
        @options = options
        @browser = FileBrowser.new(painter, buttons)
        @confirmation = Confirmation.new(painter, buttons)
        @name_field = NameField.new(painter)
        @drive_types = DriveTypes.new(painter, buttons)
        @snapshots = snapshots
        @browsing = nil
        @browse_from = media_path.empty? ? Dir.pwd : File.dirname(File.expand_path(media_path))
        @computer = nil
      end

      def open? = !@browsing.nil? || @confirmation.open? || @name_field.open? || @drive_types.open?

      # Opens the browser on the files for `kind`: :disk, :tape, :cartridge,
      # :program, or :snapshot, which starts in the saves folder.
      def browse(kind)
        @browsing = kind
        extensions = case kind
                     when :cartridge then @media.cartridge_extensions
                     when :disk then @media.disk_extensions
                     when :program then programs
                     else EXTENSIONS.fetch(kind)
                     end
        @browser.open(kind == :snapshot ? Badline.data_folder("saves") : @browse_from, extensions)
      end

      # Lists the drive types, with `model` the one on the bus.
      def pick_drive(model) = @drive_types.open(model)

      # Asks for a save's name, starting from `name`.
      def ask_name(name) = @name_field.open("SAVE AS", name)

      # Loads the save at `path` into a new machine, and returns :swap, or
      # nil when it won't load.
      def load(path)
        return nil unless @snapshots.load(path)

        @computer = @snapshots.computer
        :swap
      end

      def ask_remove = @confirmation.ask(:remove, @media.cartridge_name)

      # Puts a dropped disk or tape in its device, or asks before a
      # cartridge, a Plus/4's raw ROM image among them, or a program
      # starts, and says whether it asks. Other files are left alone.
      def drop(path)
        extension = File.extname(path).downcase
        return @media.insert(:disk, path) && false if @media.disk_extensions.include?(extension)
        return @media.insert(:tape, path) && false if EXTENSIONS[:tape].include?(extension)
        return false unless programs.include?(extension)

        @confirmation.ask(@media.cartridge_extensions.include?(extension) ? :cartridge : :start, path)
        true
      end

      # Handles a key, and returns :resume or :swap once a question is
      # answered yes, or nil.
      def key(scancode)
        return browsed(@browser.key(scancode)) unless @browsing.nil?
        return drive_key(scancode) if @drive_types.open?
        if @name_field.open? && !@confirmation.open?
          return named(@name_field.key(scancode, SDL.event_mod(SDL.event).anybits?(SDL::KMOD_SHIFT)))
        end
        return answer(:cancel) if scancode == Keys::ESCAPE
        return answer(@buttons.focus) if [Keys::RETURN, Keys::SPACE].include?(scancode)

        direction = Keys::DIRECTIONS[scancode]
        @buttons.shift(direction == :up ? -1 : 1, 1) if %i[up down].include?(direction)
        nil
      end

      # Handles a click on the browser's list at `top`, on a question's
      # answer, `action`, or on a drive type.
      def click(action, top)
        return browsed(@browser.click(top)) if action == :browse
        return picked(action) if @drive_types.open?

        answer(action)
      end

      def scroll(rows) = @browser.scroll(rows)

      def draw(left, top, width)
        return @browser.draw(left, top, width, TITLES.fetch(@browsing)) unless @browsing.nil?
        return @confirmation.draw(left, top) if @confirmation.open?
        return @drive_types.draw(left, top, width) if @drive_types.open?

        @name_field.draw(left, top, width)
      end

      private

      # What Quick open and a drop start: every medium, and the cartridges
      # the machine takes, or on the KIM-1 its programs.
      def programs
        return Media::KIM1Media::EXTENSIONS if @media.kim1?

        (EXTENSIONS[:program] + @media.cartridge_extensions).uniq
      end

      # Puts the disk or tape picked in, or asks before a cartridge or
      # Quick open power cycles the machine, and leaves the browser, as Esc
      # does.
      def browsed(picked)
        return nil if picked.nil?

        kind = @browsing
        @browse_from = @browser.directory unless kind == :snapshot
        @browsing = nil
        return nil if picked == :cancel
        return load(picked) if kind == :snapshot

        if %i[disk tape].include?(kind)
          @media.insert(kind, picked)
        else
          @confirmation.ask(kind == :cartridge ? :cartridge : :start, picked)
        end
        nil
      end

      # Up and Down move along the drive types, Return or Space picks one,
      # and Left or Esc goes back to the page.
      def drive_key(scancode)
        return picked(@buttons.focus) if [Keys::RETURN, Keys::SPACE].include?(scancode)

        direction = Keys::DIRECTIONS[scancode]
        if scancode == Keys::ESCAPE || direction == :left
          @drive_types.close
          @buttons.focus = :drive_type
        elsif %i[up down].include?(direction)
          @buttons.shift(direction == :up ? -1 : 1, 1)
        end
        nil
      end

      # Puts the drive type `action` stands for on the bus, and goes back
      # to the page.
      def picked(action)
        model = @drive_types.model_for(action)
        return nil if model.nil?

        @drive_types.close
        @buttons.focus = :drive_type
        @media.drive_type(model)
        nil
      end

      # Saves the machine under the name typed once Return takes it, and
      # asks first when a save has that name already.
      def named(result)
        name = @name_field.text.strip
        if result == :cancel
          @name_field.close
        elsif result == :done && name.empty?
          @name_field.refuse("TYPE A NAME")
        elsif result == :done
          @snapshots.named?(name) ? @confirmation.ask(:overwrite, name) : save_as(name)
        end
        nil
      end

      def save_as(name, replace: false)
        @name_field.close if @snapshots.save_named(name, replace:)
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
        when :overwrite then save_as(path, replace: true) && nil
        else
          @computer = @media.start(@options, path)
          @computer.nil? ? nil : :swap
        end
      end
    end
  end
end
