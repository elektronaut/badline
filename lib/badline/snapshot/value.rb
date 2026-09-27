# frozen_string_literal: true

module Badline
  module Snapshot
    # The tags and the classification the machine state encoding shares
    # between writing and reading.
    module Value
      NIL_VALUE = 0
      TRUE_VALUE = 1
      FALSE_VALUE = 2
      INTEGER = 3
      FLOAT = 4
      SYMBOL = 5
      NODE = 6
      CONSTANT = 7
      HOST = 8
      RANGE = 9
      FROZEN_STRING = 10
      CLASS = 11

      ARRAY = 1
      HASH = 2
      STRING = 3
      OBJECT = 4
      STRUCT = 5
      DATA = 6
      PROC = 7
      METHOD = 8

      # How an array of integers is packed.
      VALUES = 0
      BYTES = 1
      WORDS = 2

      # A reference to the node written with this id.
      Ref = Data.define(:id)
      # A reference to an object the Registry names.
      Constant = Data.define(:path)
      # Something outside the machine, such as a host device or a callback
      # the front end installed. A restore keeps what the target machine has
      # in its place.
      Host = Data.define

      HOST_VALUE = Host.new

      module_function

      def immediate?(value)
        value.nil? || value == true || value == false || value.is_a?(Integer) || value.is_a?(Float) ||
          value.is_a?(Symbol)
      end

      # A class's name, whatever the class defines `name` to be.
      def class_name(klass) = Registry::MODULE_NAME.bind_call(klass)

      # Badline's own classes, apart from the front end's, hold machine
      # state. Everything else is the host's.
      def machine_class?(klass)
        name = class_name(klass)
        return false unless name&.start_with?("Badline::")

        !Registry.skipped?(name)
      end

      # The class a snapshot names, which must be one of the machine's own.
      def machine_class(name)
        klass = Object.const_get(name) if name.start_with?("Badline::")
        raise FormatError, "the snapshot names #{name}, which isn't part of the machine" unless
          klass.is_a?(Class) && machine_class?(klass)

        klass
      rescue NameError
        raise FormatError, "this badline has no class #{name}, which the snapshot names"
      end
    end
  end
end
