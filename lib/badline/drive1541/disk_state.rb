# frozen_string_literal: true

require "badline/media/extensions"

module Badline
  class Drive1541
    class Disk
      # Saving and restoring a Disk for a snapshot: the image by its path,
      # and every half track as the head sees it, with those written since
      # the last flush. The image itself is read again from its host file,
      # where there still is one.
      module State
        # The image's path, expanded, and whether it was opened read-only,
        # for a disk from Disk.open. Nil for a disk made another way.
        attr_reader :path, :read_only

        # Whether the image is a .g64 or .g71, by its name.
        def self.g64?(path) = Media::Extensions.kind(path) == :gcr

        # A disk for the image at the path (Disk.image_for), its tracks left
        # for the state.
        def self.reopen(path, read_only) = Disk.new(Disk.image_for(path, read_only)).opened(path, read_only)

        # The disk a state from save_state describes: +current+ when it was
        # opened from the same image the same way, and otherwise a disk for
        # the image at the path the state names. Where no file is at that
        # path, the disk has no image and is write-protected, and a
        # detached reader always gets one without an image. Either way its
        # tracks come from the state.
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

          reopen(path, read_only)
        end

        # Notes the image's path and how it was opened.
        def opened(path, read_only)
          @path = File.expand_path(path)
          @read_only = read_only
          self
        end

        def save_state(out)
          out.optional_string(@path).boolean(@read_only)
          @tracks.each do |track|
            out.boolean(!track.nil?)
            save_track(track, out) if track
          end
          out.ints(@written.keys)
        end

        def load_tracks(input)
          @tracks.each_index do |half_track|
            @tracks[half_track] = input.boolean? ? load_track(input) : nil
          end
          @written.clear
          input.ints.each { |half_track| @written[half_track] = true }
        end

        private

        def save_track(track, out)
          out.int(track.zone).boolean(!track.speeds.nil?)
          out.ints(track.speeds) if track.speeds
          out.blob(track.bytes)
        end

        def load_track(input)
          zone = input.int
          speeds = input.boolean? ? input.ints : nil
          Track.new(input.blob, zone, speeds)
        end
      end
    end
  end
end
