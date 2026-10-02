# frozen_string_literal: true

module Badline
  class Options
    # One option of the table: its flags and value as the help shows them
    # (`-s, --subtune N`), what it does, the help section it's listed in, the
    # mode it needs (:window, :headless or :either), and the build that
    # takes it (:native, :ruby or :both).
    class Option
      attr_reader :usage, :name, :short, :value, :text, :section, :needs, :build

      def initialize(usage, text, section:, needs: :either, build: :both)
        @usage = usage.start_with?("--") ? "    #{usage}" : usage
        words = usage.split
        @short = words.size > 1 && words[1].start_with?("--") ? words[0].delete_suffix(",") : ""
        @name = @short.empty? ? words[0] : words[1]
        @value = words.last.start_with?("-") ? "" : words.last
        @text = text
        @section = section
        @needs = needs
        @build = build
      end

      def valued? = !@value.empty?

      def named?(flag) = flag == @name || (!@short.empty? && flag == @short)
    end
  end
end
