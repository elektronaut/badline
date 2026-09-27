# frozen_string_literal: true

module Badline
  module Snapshot
    # Puts decoded machine state into a machine, in place. Each node is
    # matched with the object the target holds in the same place, when that
    # is of the same class and not already taken, and that object takes the
    # node's state. Only nodes with nothing to match are built anew. So the
    # target keeps its identity wherever the two machines have the same
    # shape, and with it the callbacks bound to it, which can't be written
    # to a file: the front end's hooks, the traps a mounted drive installs
    # and the lines between the chips.
    #
    # A host value keeps whatever the target holds in its place. A callback
    # the snapshot's machine had and the target lacks is lost, and one the
    # target has and the snapshot's machine lacked is dropped.
    class StateRestorer
      include Value

      def initialize(records, registry = Registry.current)
        @records = records
        @registry = registry
        @objects = {}
        @taken = {}.compare_by_identity
        @queue = []
        @freeze = []
      end

      def restore(root)
        take(0, root)
        drain
        root
      end

      # The value `ref` stands for, built on its own, for a piece of the
      # snapshot's machine the target has to be given before the restore.
      def build_value(value)
        resolve(value, nil).tap { drain }
      end

      private

      def drain
        until @queue.empty?
          id, object = @queue.shift
          fill(@records[id], object)
        end
        @freeze.each(&:freeze)
        @freeze.clear
      end

      def resolve(value, hint)
        case value
        when Ref then node(value.id, hint)
        when Constant then @registry.fetch(value.path)
        when Host then host?(hint) ? hint : nil
        else value
        end
      end

      def host?(object) = !object.nil? && !Value.immediate?(object)

      def node(id, hint)
        return @objects[id] if @objects.key?(id)

        record = @records.fetch(id) { raise FormatError, "machine state refers to missing node #{id}" }
        return data(id, record, hint) if record.is_a?(StateReader::DataRecord)

        object = reusable?(record, hint) ? hint : build(record)
        object && take(id, object)
      end

      def take(id, object)
        @objects[id] = object
        @taken[object] = true
        @queue << [id, object]
        object
      end

      def reusable?(record, hint)
        return false if hint.nil? || hint.frozen? || @taken.key?(hint) || @registry.include?(hint)

        same_kind?(record, hint)
      end

      def same_kind?(record, hint)
        case record
        when StateReader::ArrayRecord then hint.instance_of?(Array)
        when StateReader::HashRecord then hint.instance_of?(Hash) && (record.identity || !hint.compare_by_identity?)
        when StateReader::StringRecord then hint.instance_of?(String)
        when StateReader::ProcRecord then hint.is_a?(Proc)
        when StateReader::MethodRecord then hint.is_a?(Method)
        else Value.class_name(hint.class) == record.class_name
        end
      end

      # Callbacks aren't built from a snapshot: without one in the target
      # to match, the slot is left empty.
      def build(record)
        case record
        when StateReader::ArrayRecord then []
        when StateReader::HashRecord then record.identity ? {}.compare_by_identity : {}
        when StateReader::StringRecord then String.new
        when StateReader::ProcRecord, StateReader::MethodRecord then nil
        else Value.machine_class(record.class_name).allocate
        end
      end

      def data(id, record, hint)
        klass = Value.machine_class(record.class_name)
        members = record.fields.to_h do |member, value|
          [member, resolve(value, hint.is_a?(klass) ? hint.public_send(member) : nil)]
        end
        @objects[id] = klass.new(**members)
      end

      def fill(record, object)
        case record
        when StateReader::ArrayRecord then fill_array(record, object)
        when StateReader::HashRecord then fill_hash(record, object)
        when StateReader::StringRecord then object.replace(record.bytes)
        when StateReader::ProcRecord then fill_proc(record, object)
        when StateReader::MethodRecord then resolve(record.receiver, object.receiver)
        when StateReader::StructRecord then fill_struct(record, object)
        else fill_ivars(record.ivars, object)
        end
      end

      # A callback the target has no match for drops out of its list.
      def fill_array(record, array)
        old = array.dup
        items = []
        record.items.each_with_index do |item, i|
          value = resolve(item, old[i])
          items << value unless value.nil? && callback?(item)
        end
        array.replace(items)
        @freeze << array if record.frozen
      end

      def callback?(item)
        item.is_a?(Host) || (item.is_a?(Ref) && @records[item.id].is_a?(StateReader::ProcRecord))
      end

      def fill_hash(record, hash)
        old = hash.dup
        hash.clear
        hash.compare_by_identity if record.identity
        hash.default = record.default unless record.default.is_a?(Host)
        record.pairs.each do |key, item|
          key = resolve(key, nil)
          value = resolve(item, old[key])
          hash[key] = value unless value.nil? && callback?(item)
        end
        @freeze << hash if record.frozen
      end

      # A block keeps its own receiver and captured variables: the node's
      # state goes into the objects they hold. Its variables aren't set, as
      # blocks made in one scope share them.
      def fill_proc(record, block)
        binding = block.binding
        resolve(record.receiver, binding.receiver)
        record.locals.each do |name, value|
          resolve(value, binding.local_variable_get(name)) if binding.local_variable_defined?(name)
        end
      end

      def fill_struct(record, struct)
        record.fields.each { |member, value| struct[member] = resolve(value, struct[member]) }
        fill_ivars(record.ivars, struct)
      end

      # Variables the snapshot's object hadn't set yet go back to nil, as
      # they read before they were set. Removing them would cost the object
      # its shape, and the interpreter its fast path to them.
      def fill_ivars(ivars, object)
        (object.instance_variables - ivars.map(&:first)).each { |name| object.instance_variable_set(name, nil) }
        ivars.each do |name, value|
          hint = object.instance_variable_get(name) if object.instance_variable_defined?(name)
          object.instance_variable_set(name, resolve(value, hint))
        end
      end
    end
  end
end
