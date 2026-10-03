# frozen_string_literal: true

module Badline
  module Frontend
    # The window's snapshots: F11 saves the machine to a new
    # badline-<date>-<time>.vsf in the working directory, and F12 goes back
    # to the snapshot last saved or opened, in a new machine. --save-snapshot
    # saves one after the last frame.
    class Snapshots
      KEYS = [Keys::F11, Keys::F12].freeze

      # The machine running, which F12 replaces with the restored one.
      attr_accessor :computer

      def initialize(computer, options)
        @computer = computer
        @last = options.snapshot? ? options.media_path.to_s : ""
        @at_finish = options.save_snapshot
      end

      # Saves or restores for F11 or F12, and says whether a restored
      # machine now runs in place of the one before.
      def key(scancode)
        return restore if scancode == Keys::F12

        save if scancode == Keys::F11
        false
      end

      # Saves the machine, and warns when it can't.
      def save(path = "badline-#{Time.now.strftime('%Y%m%d-%H%M%S')}.vsf")
        @computer.save_snapshot(path)
        @last = path
        puts "Saved #{path}"
      rescue Snapshot::FormatError, SystemCallError => e
        warn "badline: #{path}: #{e.message}"
      end

      # Restores the snapshot last saved or opened into a new machine, and
      # warns when it fails, leaving the machine running as it was.
      def restore
        if @last.empty?
          puts "No snapshot to restore, F11 saves one"
          return false
        end

        @computer = Snapshot.load(@last) { |line| puts line }
        puts "Restored #{@last}"
        true
      rescue Snapshot::FormatError, SystemCallError => e
        warn "badline: #{@last}: #{e.message}"
        false
      end

      def finish
        save(@at_finish) unless @at_finish.empty?
      end
    end
  end
end
