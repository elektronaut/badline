# frozen_string_literal: true

module Badline
  module Snapshot
    # Names every object reachable from Badline's constants and class-level
    # instance variables by the path that reaches it, such as
    # `Badline::CPU::FETCH_PLAN` or `Badline::CPU::MICROCODE/12/plan`. The
    # machine points into these tables — the CPU at the plan of the
    # instruction it runs, the SID at its model's waveform tables — and a
    # snapshot names them rather than copying them, so a restored machine
    # points at this process's own, as the code compares some by identity.
    #
    # The front end's namespaces are left out: they hold host devices, and
    # aren't loaded everywhere a snapshot is.
    class Registry
      SKIPPED = %w[Badline::GUI Badline::SDL Badline::Audio Badline::Snapshot].freeze
      MODULE_NAME = ::Module.instance_method(:name)

      def self.current = new

      # Whether a class or module belongs to the front end.
      def self.skipped?(name) = SKIPPED.any? { |skipped| name == skipped || name.start_with?("#{skipped}::") }

      def initialize
        @paths = {}.compare_by_identity
        @objects = {}
        @modules = {}.compare_by_identity
        visit_module(Badline)
      end

      def path(object) = @paths[object]

      def include?(object) = @paths.key?(object)

      def fetch(path)
        @objects.fetch(path) { raise FormatError, "this badline has no #{path}, which the snapshot refers to" }
      end

      private

      def visit_module(mod)
        return if @modules.key?(mod)

        @modules[mod] = true
        name = MODULE_NAME.bind_call(mod)
        mod.instance_variables.each { |ivar| visit(mod.instance_variable_get(ivar), "#{name}.#{ivar}") }
        mod.constants(false).sort.each { |constant| visit_constant(mod, name, constant) }
      end

      def visit_constant(mod, name, constant)
        return if mod.autoload?(constant)

        value = mod.const_get(constant, false)
        if value.is_a?(::Module)
          visit_module(value) if namespace?(value)
        else
          visit(value, "#{name}::#{constant}")
        end
      end

      def namespace?(mod)
        name = MODULE_NAME.bind_call(mod)
        name&.start_with?("Badline::") && !Registry.skipped?(name)
      end

      # Walks depth first with an explicit stack: the tables nest deeply.
      def visit(root, root_path)
        stack = [[root, root_path]]
        until stack.empty?
          object, path = stack.pop
          next if Value.immediate?(object) || object.is_a?(::Module) || @paths.key?(object)

          @paths[object] = path
          @objects[path] = object
          children(object, path) { |child, child_path| stack << [child, child_path] }
        end
      end

      def children(object, path, &)
        case object
        when Array then object.each_with_index { |item, i| yield item, "#{path}/#{i}" }
        when Hash then hash_children(object, path, &)
        when Struct, Data then object.to_h.each { |member, value| yield value, "#{path}/#{member}" }
        when Proc, Method, String, Range then nil
        else object.instance_variables.each { |ivar| yield object.instance_variable_get(ivar), "#{path}/#{ivar}" }
        end
      end

      # Keys that print the same in every process name their values.
      # Others fall back on the insertion order.
      def hash_children(hash, path)
        hash.each_with_index do |(key, value), i|
          label = Value.immediate?(key) || key.is_a?(String) ? key.inspect : "##{i}"
          yield key, "#{path}/key#{i}"
          yield value, "#{path}/#{label}"
        end
      end
    end
  end
end
