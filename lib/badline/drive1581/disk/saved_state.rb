# frozen_string_literal: true

module Badline
  class Drive1581
    class Disk
      # Saving and restoring a Disk for a snapshot: the image by its path,
      # and every track the head wrote since the disk went in, with those
      # written since the last flush. The rest come from the image, read
      # again from its host file where there still is one.
      module SavedState
        # The image's path, expanded, and whether it was opened read-only,
        # for a disk from Disk.open. Nil for a disk made another way.
        attr_reader :path, :read_only

        # The disk a state from save_state describes: +current+ when it was
        # opened from the same image the same way, and otherwise a disk for
        # the image at the path the state names. Where no file is at that
        # path, the disk has no image and is write-protected, and a
        # detached reader always gets one without an image.
        def self.load(input, current)
          path = input.optional_string
          read_only = input.boolean?
          disk = current if current && !path.nil? && current.path == path && current.read_only == read_only
          disk ||= fresh(path, read_only, input.detached?)
          disk.load_tracks(input)
          disk
        end

        def self.fresh(path, read_only, detached)
          return Disk.new if path.nil? || detached
          return Disk.new.opened(path, true) unless File.file?(path)

          Disk.open(path, read_only:)
        end

        # Notes the image's path and how it was opened.
        def opened(path, read_only)
          @path = File.expand_path(path)
          @read_only = read_only
          self
        end

        def save_state(out)
          out.optional_string(@path).boolean(@read_only)
          changed = @changed.keys.sort
          out.ints(changed)
          changed.each { |index| save_track(@tracks[index], out) }
          out.ints(@written.keys)
        end

        def load_tracks(input)
          @changed.clear
          input.ints.each do |index|
            @tracks[index] = load_track(input)
            @changed[index] = true
          end
          @written.clear
          input.ints.each { |index| @written[index] = true }
        end

        private

        def save_track(track, out)
          out.int(track.sectors.length)
          track.sectors.each do |sector|
            save_field(sector.id, out)
            out.boolean(!sector.data.nil?)
            save_field(sector.data, out) if sector.data
          end
        end

        def save_field(field, out)
          out.int(field.mark).ints(field.bytes).boolean(field.good).boolean(field.deleted)
        end

        def load_track(input)
          Track.new(Array.new(input.int) do
            id = load_field(input)
            Track::Sector.new(id, input.boolean? ? load_field(input) : nil)
          end)
        end

        def load_field(input) = Track::Field.new(input.int, input.ints, input.boolean?, input.boolean?)
      end
    end
  end
end
