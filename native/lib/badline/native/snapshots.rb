# frozen_string_literal: true

module Badline
  module Native
    # The window's snapshots: F11 saves the machine to a new
    # badline-<date>-<time>.vsf in the working directory, and F12 goes back
    # to the snapshot last saved or opened. --save-snapshot saves one after
    # the last frame.
    class Snapshots
      KEYS = [Keys::F11, Keys::F12].freeze

      def initialize(computer, options)
        @computer = computer
        @last = options.snapshot? ? options.media : ""
        @at_finish = options.save_snapshot
      end

      # Saves or restores for F11 or F12, and says whether the machine was
      # restored.
      def key(scancode)
        return restore if scancode == Keys::F12

        save if scancode == Keys::F11
        false
      end

      def save(path = "badline-#{Time.now.strftime('%Y%m%d-%H%M%S')}.vsf")
        @computer.save_snapshot(path)
        @last = path
        puts "Saved #{path}"
      end

      def restore
        if @last.empty?
          puts "No snapshot to restore, F11 saves one"
          return false
        end

        @computer.restore_snapshot(@last) { |line| puts line }
        puts "Restored #{@last}"
        true
      rescue Snapshot::FormatError => e
        warn "badline: #{@last}: #{e.message}"
        false
      end

      def finish
        save(@at_finish) unless @at_finish.empty?
      end
    end
  end
end
