# frozen_string_literal: true

module Badline
  module Media
    # An ordered list of media files to go through one at a time, such as
    # the tunes of a player. Each entry is a file and the part of it to
    # start on, counting from 1, out of the parts the file holds: a .sid
    # tune's songs, say, or 1 of 1 for media with no parts.
    #
    # #forward and #back step through the entries, and return the entry
    # they moved to, or nil where they stay put. With #loop? they wrap
    # around at either end, and with #shuffle? they follow a shuffled
    # order that starts from the current entry. With #all_parts? an entry
    # plays every one of its parts before the queue moves on: #forward and
    # #back step through them first, starting a later entry on its first
    # part and an earlier one on its last.
    #
    # `shuffle`, if given, returns the entry indices it's given in a new
    # order in place of Array#shuffle.
    class Queue
      # A file and the part of it to start on.
      class Entry
        attr_reader :path, :part, :parts

        def initialize(path, part: 1, parts: 1)
          @path = path
          @part = part
          @parts = parts
        end
      end

      attr_reader :part

      def initialize(entries, all_parts: true, shuffle: nil)
        @entries = entries
        @shuffler = shuffle
        @order = (0...entries.size).to_a
        @position = 0
        @part = entries.empty? ? 0 : entries.first.part
        @all_parts = all_parts
        @shuffle = false
        @loop = false
      end

      def size = @entries.size

      def empty? = @entries.empty?

      def entry = empty? ? nil : @entries[@order[@position]]

      def all_parts? = @all_parts

      def shuffle? = @shuffle

      def loop? = @loop

      def toggle_all_parts = @all_parts = !@all_parts

      def toggle_loop = @loop = !@loop

      def toggle_shuffle
        return @shuffle = !@shuffle if empty?

        current = @order[@position]
        @shuffle = !@shuffle
        @order = (0...size).to_a
        @order = [current] + shuffled(@order - [current]) if @shuffle
        @position = @order.index(current)
        @shuffle
      end

      def forward
        return if empty?
        return step_part(1) if @all_parts && @part < entry.parts

        move(@position + 1, forward: true)
      end

      def back
        return if empty?
        return step_part(-1) if @all_parts && @part > 1

        move(@position - 1, forward: false)
      end

      private

      def step_part(step)
        @part += step
        entry
      end

      def move(position, forward:)
        return unless position.between?(0, size - 1) || @loop

        @position = position % size
        @part = if !@all_parts then entry.part
                elsif forward then 1
                else entry.parts
                end
        entry
      end

      def shuffled(indices) = @shuffler ? @shuffler.call(indices) : indices.shuffle
    end
  end
end
