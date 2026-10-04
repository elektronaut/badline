# frozen_string_literal: true

module Badline
  module Media
    # The disks of a set a disk image belongs to, found by name in its
    # folder: images whose names differ only in their disk, side or part
    # markers, such as "Disk 1", "Side B", "d2", "(Disk 1 of 3)", ordered
    # by those markers. A name with no marker can end in a number or a
    # letter, as in game_1.d64 and game_2.d64, which counts only when the
    # folder has the first of the set too.
    #
    # A list in the disk's folder that names it (DiskList) gives its set
    # ahead of the names.
    module DiskSet
      KINDS = %w[disk disc side part].freeze
      EXTENSIONS = %w[.d64 .d71 .d81 .g64].freeze

      # The paths of the set's disks in order, or just `path` when it
      # belongs to none. A list's set is the disks it lists.
      def self.around(path)
        return DiskList.disks(path) if DiskList.list?(path)
        return [path] unless EXTENSIONS.include?(File.extname(path).downcase)

        listed = DiskList.beside(path)
        listed.empty? ? named(path) : listed
      end

      # The set of the disk's name.
      def self.named(path)
        extension = File.extname(path).downcase
        marked = !parse(stem(path))[1].negative?
        base = key(stem(path), marked)[0]
        found = siblings(File.dirname(path), extension, base, marked)
        return [path] if found.size < 2 || (!marked && found.none? { |pair| pair[0] == 1 })

        found.sort_by { |pair| pair[0] }.map { |pair| File.join(File.dirname(path), pair[1]) }
      end

      # The name's words without their markers, joined, and the order the
      # markers give it, -1 for none.
      def self.parse(stem)
        words = words(stem)
        base = []
        values = []
        index = 0
        index = take(words, index, base, values) while index < words.size
        [base.join(" "), order(values)]
      end

      # The words before a trailing number or letter, joined, and its
      # order, -1 for a name that doesn't end in one.
      def self.trailing(stem)
        words = words(stem)
        last = words.last.to_s
        return ["", -1] if words.size < 2 || !value?(last) || last.length > 2

        [words[0, words.size - 1].join(" "), value(last)]
      end

      def self.words(stem) = stem.downcase.split(/[^a-z0-9]+/).reject(&:empty?)

      def self.stem(path) = File.basename(path, File.extname(path))

      def self.key(stem, marked) = marked ? parse(stem) : trailing(stem)

      # The order and name of each image in the folder in the set.
      def self.siblings(directory, extension, base, marked)
        found = []
        children(directory).each do |name|
          next unless File.extname(name).downcase == extension

          name_key = key(stem(name), marked)
          found << [name_key[1], name] if name_key[0] == base && !name_key[1].negative?
        end
        found
      end

      # Adds the word at `index` to the base, or its marker's value to the
      # values, and returns the index of the next word.
      def self.take(words, index, base, values)
        word = words[index]
        following = words[index + 1].to_s
        if KINDS.include?(word) && value?(following)
          values << value(following)
          index += 2
          index += 2 if words[index] == "of" && words[index + 1].to_s.match?(/\A\d+\z/)
          index
        elsif marker?(word)
          values << value(word.sub(/\A(disk|disc|side|part|d|s)/, ""))
          index + 1
        else
          base << word
          index + 1
        end
      end

      def self.marker?(word) = word.match?(/\A(disk|disc|side|part)(\d+|[a-z])\z/) || word.match?(/\A[ds]\d+\z/)

      def self.value?(word) = word.match?(/\A(\d+|[a-z])\z/)

      # A number counts as itself and a letter by its place in the
      # alphabet, so side A is 1.
      def self.value(word) = word.match?(/\A\d+\z/) ? word.to_i : word.ord - 96

      def self.order(values)
        return -1 if values.empty?

        values.reduce(0) { |order, value| (order * 1000) + value }
      end

      def self.children(directory)
        Dir.children(directory)
      rescue SystemCallError
        []
      end
    end
  end
end
