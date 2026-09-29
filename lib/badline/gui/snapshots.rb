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

      # The machine the window starts with: for a .vsf the machine it holds,
      # built with that machine's chip models, which F12 goes back to, and
      # otherwise one built from the machine options (Application.new) with
      # the media attached.
      def boot(media_path, machine, media)
        return load(media_path) if Snapshots.snapshot?(media_path)

        sid_model = machine[:sid_model] || Media.sid_model(media_path)
        Computer.new(sid_model:, **machine.slice(:reu)).tap do |computer|
          Media::TrueDrive.plug(computer) if machine[:true_drive]
          puts Media.attach(computer, media_path, **media) if media_path
        end
      end

      # A new machine, built as the snapshot's was and restored from it.
      def load(path)
        computer = Snapshot.load(path) { |line| puts line }
        @last = path
        puts "Restored #{path}"
        computer
      end

      # Saves the machine, and warns when it can't.
      def save(computer)
        path = "badline-#{Time.now.strftime('%Y%m%d-%H%M%S')}.vsf"
        computer.save_snapshot(path)
        @last = path
        puts "Saved #{path}, F12 restores it"
      rescue Snapshot::FormatError, SystemCallError => e
        warn "badline: #{path}: #{e.message}"
      end

      # A new machine restored from the snapshot last saved or opened, or
      # nil when there is none or it fails, which it warns about.
      def restore
        return load(@last) if @last

        puts "No snapshot to restore, F11 saves one"
        nil
      rescue Snapshot::FormatError, SystemCallError => e
        warn "badline: #{@last}: #{e.message}"
        nil
      end
    end
  end
end
