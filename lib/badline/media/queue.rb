# frozen_string_literal: true

module Badline
  module Media
    # An ordered list of media files to go through one at a time, such as
    # the tunes of a player. Each entry is a file and the part of it to
    # start on, counting from 1, out of the parts the file holds: a .sid
    # tune's subtunes, say, or 1 of 1 for media with no parts.
    #
    # #next_entry and #previous_entry step through the entries, and
    # #next_part and #previous_part through the current entry's parts,
    # stopping at its ends. Each returns the entry it moved to, or nil
    # where it stays put. With #loop? the entry steps wrap around at
    # either end, and with #shuffle? they follow a shuffled order that
    # starts from the current entry. #all_parts? decides where #advance
    # goes once a part has played out: on through the entry's parts, or
    # to the next entry. An entry stepped to starts on its first part
    # with #all_parts?, otherwise on its own.
    #
    # `shuffle`, if given, returns the entry indices it's given in a new
    # order in place of Array#shuffle. `build`, if given, turns the paths
    # #add is given into entries.
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

      # The files `paths` name, in order: a file as given, and a directory
      # as every file below it with the extension, in path order.
      def self.files(paths, extension)
        paths.flat_map { |path| File.directory?(path) ? below(path, extension).sort : [path] }
      end

      def self.below(directory, extension)
        paths = []
        Dir.children(directory).each do |name|
          path = File.join(directory, name)
          if File.directory?(path)
            paths.concat(below(path, extension))
          elsif File.extname(name).casecmp?(extension)
            paths << path
          end
        end
        paths
      end
      private_class_method :below

      def initialize(entries, all_parts: false, shuffle: nil, build: nil)
        @entries = entries
        @shuffler = shuffle
        @builder = build
        @order = (0...entries.size).to_a
        @position = 0
        @part = entries.empty? ? 0 : entries.first.part
        @all_parts = all_parts
        @shuffle = false
        @loop = false
      end

      def size = @entries.size

      def empty? = @entries.empty?

      # Where the current entry stands in the order played, from 1.
      def position = empty? ? 0 : @position + 1

      def entry = empty? ? nil : @entries[@order[@position]]

      def all_parts? = @all_parts

      def shuffle? = @shuffle

      def loop? = @loop

      # Puts the entries `build` makes of the paths at the end of the order,
      # shuffled or not. An empty queue starts on the first of them.
      def add(paths)
        return if @builder.nil?

        started = empty?
        first = @entries.size
        @entries.concat(@builder.call(paths))
        @order.concat((first...@entries.size).to_a)
        @part = entry.part if started && !empty?
      end

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

      def next_entry
        return if empty?

        move(@position + 1)
      end

      def previous_entry
        return if empty?

        move(@position - 1)
      end

      def next_part
        return if empty? || @part >= entry.parts

        @part += 1
        entry
      end

      def previous_part
        return if empty? || @part <= 1

        @part -= 1
        entry
      end

      # Where to go once the current part has played to its end: the
      # entry's next part with #all_parts?, otherwise the next entry.
      def advance
        return next_part if @all_parts && !empty? && @part < entry.parts

        next_entry
      end

      private

      def move(position)
        return unless position.between?(0, size - 1) || @loop

        @position = position % size
        @part = @all_parts ? 1 : entry.part
        entry
      end

      def shuffled(indices) = @shuffler ? @shuffler.call(indices) : indices.shuffle
    end
  end
end
