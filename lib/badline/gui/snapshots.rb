# frozen_string_literal: true

module Badline
  module GUI
    # The window's snapshots: a .vsf opened as the media, F11 saving the
    # machine to a new badline-<date>-<time>.vsf in the working directory,
    # and F12 going back to the snapshot last saved or opened.
    class Snapshots
      def self.snapshot?(path) = !path.nil? && File.extname(path).casecmp?(".vsf")

      def initialize
        @last = nil
      end

      # A new machine, built as the snapshot's was and restored from it.
      def load(path)
        @last = path
        Snapshot.load(path) { |line| puts line }.tap { puts "Restored #{path}" }
      end

      def save(computer)
        path = "badline-#{Time.now.strftime('%Y%m%d-%H%M%S')}.vsf"
        computer.save_snapshot(path)
        @last = path
        puts "Saved #{path}, F12 restores it"
      end

      # Restores the snapshot last saved or opened into the machine, and
      # says whether it did.
      def restore(computer)
        unless @last
          puts "No snapshot to restore, F11 saves one"
          return false
        end

        computer.restore_snapshot(@last) { |line| puts line }
        puts "Restored #{@last}"
        true
      rescue Snapshot::FormatError => e
        warn "badline: #{@last}: #{e.message}"
        false
      end
    end
  end
end
