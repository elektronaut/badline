# frozen_string_literal: true

module Badline
  module Snapshot
    # Encodes the machine's whole state: every object reachable from the
    # Computer through its instance variables, each written once and
    # referred to by id, so objects the machine shares stay shared. Tables
    # the Registry names are written as their path, and host objects as a
    # placeholder. A callback's receiver and captured variables are part of
    # the machine too, as a KERNAL trap keeps its state in the object its
    # block runs on.
    class StateWriter
      include Value

      def self.encode(root, registry = Registry.current)
        new(registry).encode(root)
      end

      def initialize(registry)
        @registry = registry
        @out = String.new(capacity: 1 << 20, encoding: Encoding::BINARY)
        @ids = {}.compare_by_identity
        @queue = []
        @symbols = {}
      end

      def encode(root)
        @ids[root] = 0
        @queue << root
        index = 0
        while index < @queue.length
          record(@queue[index])
          index += 1
        end
        @out
      end

      private

      def value(object)
        case object
        when nil then byte(NIL_VALUE)
        when true then byte(TRUE_VALUE)
        when false then byte(FALSE_VALUE)
        when Integer then byte(INTEGER).then { integer(object) }
        when Float then byte(FLOAT).then { @out << [object].pack("E") }
        when Symbol then symbol(object)
        else reference(object)
        end
      end

      def reference(object)
        if (path = @registry.path(object)) then byte(CONSTANT).then { string(path) }
        elsif object.is_a?(Class) && machine_class?(object) then byte(CLASS).then { string(Value.class_name(object)) }
        else structure(object)
        end
      end

      def structure(object)
        case object
        when Range then range(object)
        when String then object.frozen? ? frozen_string(object) : node(object)
        when Array, Hash, Method then node(object)
        when Proc then bound?(object) ? node(object) : byte(HOST)
        else machine_class?(object.class) ? node(object) : byte(HOST)
        end
      end

      # A block made from a method, such as `&:name`, has no binding.
      def bound?(block)
        !block.binding.nil?
      rescue ArgumentError
        false
      end

      def node(object)
        id = @ids[object]
        unless id
          id = @ids[object] = @queue.length
          @queue << object
        end
        byte(NODE)
        integer(id)
      end

      def record(object)
        case object
        when Array then array(object)
        when Hash then hash(object)
        when String then byte(STRING).then { string(object) }
        when Proc then block(object)
        when Method then method_record(object)
        when Data then data(object)
        when Struct then struct(object)
        else instance(object)
        end
      end

      def array(array)
        byte(ARRAY)
        byte(array.frozen? ? 1 : 0)
        integer(array.length)
        packing = packing(array)
        byte(packing)
        case packing
        when BYTES then @out << array.pack("C*")
        when WORDS then @out << array.pack("l<*")
        else array.each { |item| value(item) }
        end
      end

      def packing(array)
        return VALUES if array.empty? || !array.all?(Integer)

        low, high = array.minmax
        return BYTES if low >= 0 && high <= 0xff
        return WORDS if low >= -0x8000_0000 && high <= 0x7fff_ffff

        VALUES
      end

      def hash(hash)
        byte(HASH)
        byte((hash.frozen? ? 1 : 0) | (hash.compare_by_identity? ? 2 : 0))
        hash.default_proc ? byte(HOST) : value(hash.default)
        integer(hash.size)
        hash.each do |key, item|
          value(key)
          value(item)
        end
      end

      def block(block)
        byte(PROC)
        binding = block.binding
        value(binding.receiver)
        names = binding.local_variables
        integer(names.length)
        names.each do |name|
          symbol(name)
          value(binding.local_variable_get(name))
        end
      end

      def method_record(method)
        byte(METHOD)
        value(method.receiver)
        symbol(method.name)
      end

      def data(data)
        byte(DATA)
        string(Value.class_name(data.class))
        members(data.to_h)
      end

      def struct(struct)
        byte(STRUCT)
        string(Value.class_name(struct.class))
        members(struct.to_h)
        ivars(struct)
      end

      def instance(object)
        byte(OBJECT)
        string(Value.class_name(object.class))
        ivars(object)
      end

      def members(hash)
        integer(hash.size)
        hash.each do |member, item|
          symbol(member)
          value(item)
        end
      end

      def ivars(object)
        names = object.instance_variables
        integer(names.length)
        names.each do |name|
          symbol(name)
          value(object.instance_variable_get(name))
        end
      end

      def range(range)
        byte(RANGE)
        value(range.begin)
        value(range.end)
        byte(range.exclude_end? ? 1 : 0)
      end

      def frozen_string(text)
        byte(FROZEN_STRING)
        string(text.encoding.name)
        string(text)
      end

      # A symbol is spelled out the first time and numbered after.
      def symbol(name)
        byte(SYMBOL)
        if (id = @symbols[name])
          integer(id + 1)
        else
          @symbols[name] = @symbols.size
          integer(0)
          string(name.name)
        end
      end

      def string(text)
        integer(text.bytesize)
        @out << text.b
      end

      def byte(value) = @out << value.chr

      # Zigzag, then seven bits a byte, low first.
      def integer(value)
        n = value.negative? ? ((-value) << 1) - 1 : value << 1
        while n > 0x7f
          @out << ((n & 0x7f) | 0x80).chr
          n >>= 7
        end
        @out << n.chr
      end
    end
  end
end
