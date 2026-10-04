# frozen_string_literal: true

module Badline
  module Frontend
    # The window's snapshots: F11 saves the machine to the next of five
    # quicksave slots in the data folder, replacing the oldest, and F12
    # restores the newest quicksave or named save in a new machine.
    # --save-snapshot saves one after the last frame.
    class Snapshots
      KEYS = [Keys::F11, Keys::F12].freeze
      SLOTS = 5

      # The machine running, which F12 replaces with the restored one.
      attr_accessor :computer

      def initialize(computer, options)
        @computer = computer
        @at_finish = options.save_snapshot
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
        slot = next_slot(folder)
        save(slot_path(folder, slot), "quicksave #{slot}")
      rescue SystemCallError => e
        warn "badline: quicksave: #{e.message}"
      end

      # Saves the machine, and warns when it can't.
      def save(path, name = "")
        @computer.save_snapshot(path)
        puts(name.empty? ? "Saved #{path}" : "Saved #{name} to #{path}")
      rescue Snapshot::FormatError, SystemCallError => e
        warn "badline: #{path}: #{e.message}"
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

      def next_slot(folder)
        empty = (1..SLOTS).find { |slot| !File.exist?(slot_path(folder, slot)) }
        return empty unless empty.nil?

        (1..SLOTS).min_by { |slot| modified(slot_path(folder, slot)) }
      end

      def slot_path(folder, slot) = File.join(folder, "quicksave-#{slot}.vsf")

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
        slot = (1..SLOTS).find { |n| slot_path(folder, n) == path }
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
