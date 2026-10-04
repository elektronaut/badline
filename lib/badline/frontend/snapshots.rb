# frozen_string_literal: true

module Badline
  module Frontend
    # The window's snapshots: F11 saves the machine to the next of five
    # quicksave slots in the data folder, replacing the oldest, and F12
    # restores the newest quicksave or named save in a new machine. A run
    # without a frame limit also autosaves every AUTOSAVE_FRAMES frames to
    # the next of three autosave slots, which only the pause menu loads.
    # --save-snapshot saves one after the last frame.
    class Snapshots
      KEYS = [Keys::F11, Keys::F12].freeze
      SLOTS = 5
      AUTOSAVES = 3
      AUTOSAVE_FRAMES = 6000

      # The machine running, which F12 replaces with the restored one.
      attr_accessor :computer

      def initialize(computer, options)
        @computer = computer
        @at_finish = options.save_snapshot
        @autosave = options.frames.zero?
        @autosave_at = AUTOSAVE_FRAMES
      end

      # Saves or restores for F11 or F12, and says whether a restored
      # machine now runs in place of the one before.
      def key(scancode)
        return restore if scancode == Keys::F12

        quicksave if scancode == Keys::F11
        false
      end

      # Saves the machine to the first empty quicksave slot, or else to the
      # one saved longest ago, and warns when it can't.
      def quicksave
        folder = Badline.data_folder("quicksaves")
        slot = next_slot(folder, "quicksave", SLOTS)
        save(slot_path(folder, "quicksave", slot), "quicksave #{slot}")
      rescue SystemCallError => e
        warn "badline: quicksave: #{e.message}"
      end

      # Saves the machine, and warns when it can't. Says whether it saved.
      def save(path, name = "")
        @computer.save_snapshot(path)
        puts(name.empty? ? "Saved #{path}" : "Saved #{name} to #{path}")
        true
      rescue Snapshot::FormatError, SystemCallError => e
        warn "badline: #{path}: #{e.message}"
        false
      end

      # Restores the newest quicksave or named save into a new machine, and
      # warns when it fails, leaving the machine running as it was.
      def restore
        path = newest
        if path.empty?
          puts "No quicksave to restore. F11: Quicksave"
          return false
        end

        restore_from(path)
      rescue SystemCallError => e
        warn "badline: quicksave: #{e.message}"
        false
      end

      # Autosaves once the machine has run AUTOSAVE_FRAMES frames since the
      # last, quietly. A machine that can't be saved stops autosaving after
      # one warning.
      def tick(frames)
        return unless @autosave && frames >= @autosave_at

        @autosave_at = frames + AUTOSAVE_FRAMES
        folder = Badline.data_folder("autosaves")
        @computer.save_snapshot(slot_path(folder, "autosave", next_slot(folder, "autosave", AUTOSAVES)))
      rescue Snapshot::FormatError, SystemCallError => e
        @autosave = false
        warn "badline: autosave: #{e.message}"
      end

      # The snapshots in one of the data folders, `quicksaves`, `autosaves`
      # or `saves`, newest first.
      def list(name)
        folder = Badline.data_folder(name)
        paths = Dir.children(folder).select { |child| File.extname(child).casecmp?(".vsf") }
        paths.map { |child| File.join(folder, child) }.sort_by { |path| -modified(path) }
      rescue SystemCallError
        []
      end

      # Whether a save in the saves folder has the name.
      def named?(name) = File.exist?(File.join(Badline.data_folder("saves"), "#{name}.vsf"))

      # Saves the machine as `name` in the saves folder, and says whether it
      # did: a name already taken is overwritten only with `replace`.
      def save_named(name, replace: false)
        path = File.join(Badline.data_folder("saves"), "#{name}.vsf")
        return false if File.exist?(path) && !replace

        save(path, name)
      rescue SystemCallError => e
        warn "badline: #{name}: #{e.message}"
        false
      end

      # `base` and the lowest number no named save has yet.
      def free_name(base)
        folder = Badline.data_folder("saves")
        number = 1
        number += 1 while File.exist?(File.join(folder, "#{base} #{number}.vsf"))
        "#{base} #{number}"
      rescue SystemCallError
        "#{base} 1"
      end

      # Restores the snapshot at `path` into a new machine, and says whether
      # it did.
      def load(path) = restore_from(path)

      # When the snapshot at `path` was saved, as HH:MM:SS.
      def time_of(path)
        time = File.mtime(path)
        format("%<hour>02d:%<minute>02d:%<second>02d", hour: time.hour, minute: time.min, second: time.sec)
      end

      def finish
        save(@at_finish) unless @at_finish.empty?
      end

      private

      def restore_from(path)
        @computer = Snapshot.load(path) { |line| puts line }
        puts "Restored #{name_of(path)} from #{path}"
        true
      rescue Snapshot::FormatError, SystemCallError => e
        warn "badline: #{path}: #{e.message}"
        false
      end

      def next_slot(folder, kind, count)
        empty = (1..count).find { |slot| !File.exist?(slot_path(folder, kind, slot)) }
        return empty unless empty.nil?

        (1..count).min_by { |slot| modified(slot_path(folder, kind, slot)) }
      end

      def slot_path(folder, kind, slot) = File.join(folder, "#{kind}-#{slot}.vsf")

      # The .vsf in quicksaves/ or saves/ written last, or "" when there's
      # none.
      def newest
        found = ""
        found_at = 0
        %w[quicksaves saves].each do |name|
          folder = Badline.data_folder(name)
          Dir.children(folder).each do |child|
            next unless File.extname(child).casecmp?(".vsf")

            path = File.join(folder, child)
            at = modified(path)
            next unless found.empty? || at > found_at

            found = path
            found_at = at
          end
        end
        found
      end

      def name_of(path)
        folder = Badline.data_folder("quicksaves")
        slot = (1..SLOTS).find { |n| slot_path(folder, "quicksave", n) == path }
        slot.nil? ? File.basename(path, ".vsf") : "quicksave #{slot}"
      end

      # The modification time in nanoseconds.
      def modified(path)
        time = File.mtime(path)
        (time.tv_sec * 1_000_000_000) + time.nsec
      end
    end
  end
end
