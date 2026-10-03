# frozen_string_literal: true

module Badline
  module Frontend
    # The events of --at and --script. Each runs once its number of frames
    # has run: a screenshot saves that frame, and the rest act on the
    # machine before the next frame is clocked. A key or the freeze button
    # is let go Options::Event::HOLD frames after it is pressed. An event
    # that fails ends the run.
    class Timeline
      # Takes the events, --screenshot's at the last frame and whether to
      # insert disks write-protected from Options.
      def initialize(options)
        @events = options.timeline
        unless options.screenshot.empty? || options.frames.zero?
          @events += [Options::Event.new(options.frames, "screenshot", options.screenshot)]
        end
        @read_only = !options.writable?
        @program = options.program
        @releases = []
        @failed = false
      end

      # What's wrong with the events, the first key that names nothing,
      # or an empty string.
      def self.error(events)
        event = events.find { |candidate| candidate.action == "key" && !key?(candidate.argument) }
        event.nil? ? "" : "no such key: #{event.argument}"
      end

      def self.key?(name) = name == "restore" || !keyboard_key(name).nil? || !joystick_direction(name).nil?

      # The Keyboard's key for a name such as space, return or a.
      def self.keyboard_key(name)
        key = Keyboard.new.matrix.flatten.find { |candidate| candidate.to_s == name }
        key.nil? ? Keyboard::COMBINATIONS.keys.find { |candidate| candidate.to_s == name } : key
      end

      # The direction of joy1-NAME or joy2-NAME, such as up or fire.
      def self.joystick_direction(name)
        return nil unless name.start_with?("joy1-") || name.start_with?("joy2-")

        Joystick::DIRECTIONS.keys.find { |direction| direction.to_s == name[5, name.size - 5] }
      end

      # The screenshot's file name, with the frame's number in place of %d,
      # or of %Nd or %0Nd padded to N digits.
      def self.path(pattern, frame)
        start = pattern.index("%")
        finish = start.nil? ? nil : pattern.index("d", start)
        return pattern if finish.nil?

        width = pattern[start + 1, finish - start - 1]
        return pattern unless width.match?(/\A\d*\z/)

        number = frame.to_s.rjust(width.to_i, width.start_with?("0") ? "0" : " ")
        pattern[0, start] + number + pattern[finish + 1, pattern.size - finish - 1]
      end

      # The files the frame's screenshots go to.
      def screenshots(frame)
        @events.select { |event| event.frame == frame && event.action == "screenshot" }
               .map { |event| Timeline.path(event.argument, frame) }
      end

      # Whether the run ends at the frame: at a quit, or once an event failed.
      def quit?(frame) = @failed || @events.any? { |event| event.frame == frame && event.action == "quit" }

      # Whether an event failed, which ends the run.
      def failed? = @failed

      # Lets go of what was held until this frame, then runs its events, up
      # to one that fails.
      def run(computer, frame)
        @releases.each { |event| release(computer, event) if event.frame == frame }
        @releases.reject! { |event| event.frame == frame }
        @events.each { |event| perform(computer, event) if event.frame == frame && !@failed }
      end

      private

      def perform(computer, event)
        case event.action
        when "key" then press(computer, event)
        when "type" then computer.type_text(event.argument.gsub("\\n", "\r").gsub("\\r", "\r"))
        when "insert" then insert(computer, event.argument)
        when "eject" then eject(computer, event.argument)
        when "reset" then computer.reset!
        when "freeze" then freeze(computer, event)
        end
      end

      def press(computer, event)
        name = event.argument
        if name == "restore"
          computer.press_restore
          return
        end

        direction = Timeline.joystick_direction(name)
        if direction.nil?
          computer.keyboard.press(Timeline.keyboard_key(name))
        else
          joystick(computer, name).press(direction)
        end
        hold(event)
      end

      def freeze(computer, event)
        computer.press_cartridge_button
        hold(event)
      end

      def hold(event)
        @releases << Options::Event.new(event.frame + Options::Event::HOLD, event.action, event.argument)
      end

      def release(computer, event)
        return computer.release_cartridge_button if event.action == "freeze"

        name = event.argument
        direction = Timeline.joystick_direction(name)
        if direction.nil?
          computer.keyboard.release(Timeline.keyboard_key(name))
        else
          joystick(computer, name).release(direction)
        end
      end

      def joystick(computer, name) = name.start_with?("joy1-") ? computer.joystick1 : computer.joystick2

      def insert(computer, path)
        puts Media.attach(computer, path, autostart: false, disk: { read_only: @read_only })
      rescue StandardError => e
        warn "#{@program}: #{path}: #{e.message}"
        @failed = true
      end

      def eject(computer, what)
        return puts "No #{what} to eject" unless inserted?(computer, what)

        if what == "disk"
          eject_disk(computer)
        elsif what == "tape"
          computer.datasette.eject
        else
          computer.address_bus.detach_cartridge
          computer.power_cycle!
        end
        puts "Ejected the #{what}"
      end

      def inserted?(computer, what)
        return !computer.datasette.tape.nil? if what == "tape"
        return !computer.address_bus.cartridge.nil? if what == "cartridge"

        drive = Media::TrueDrive.drive(computer)
        drive.nil? ? computer.mounted? : !drive.disk.nil?
      end

      def eject_disk(computer)
        drive = Media::TrueDrive.drive(computer)
        if drive.nil?
          computer.unmount
        else
          drive.insert(nil)
        end
      end
    end
  end
end
