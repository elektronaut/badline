# frozen_string_literal: true

require "prism"

# Finds the Ruby constructs Spinel can't compile: reflection, runtime code
# generation and dynamic dispatch. Each finding is a Violation naming the
# file, the line and the construct.
class SpinelSubset
  Violation = Data.define(:path, :line, :construct) do
    def to_s = "#{path}:#{line}: #{construct}"
  end

  # Calls that are outside the subset only when the name they take is
  # computed at runtime
  COMPUTED_NAME_CALLS = %i[send public_send __send__ const_get const_set].freeze

  # Calls that are outside the subset whatever their arguments
  CALLS = %i[
    eval class_eval instance_eval module_eval
    define_method define_singleton_method
    def_delegator def_delegators
    instance_variable_get instance_variable_set
  ].freeze

  DEFINITIONS = %i[method_missing respond_to_missing?].freeze

  CONSTANTS = %i[Forwardable ObjectSpace].freeze

  # The file and construct pairs let through: the CPU's microcode plan and
  # operation dispatch, which waits on matz/spinel#4854. Any other file, or
  # any other construct in these files, fails.
  ALLOWED = [
    ["lib/badline/cpu.rb", "send with a computed name"],
    ["lib/badline/cpu/addressing.rb", "send with a computed name"],
    ["lib/badline/cpu/operations.rb", "send with a computed name"],
    ["lib/badline/cpu/stack_operations.rb", "send with a computed name"]
  ].freeze

  def self.allowed?(violation)
    ALLOWED.include?([violation.path, violation.construct])
  end

  def self.scan(paths, root:)
    paths.flat_map do |path|
      visitor = Visitor.new(path.delete_prefix("#{root}/"))
      Prism.parse_file(path).value.accept(visitor)
      visitor.violations
    end
  end

  # Walks one file's syntax tree and collects its violations
  class Visitor < Prism::Visitor
    attr_reader :violations

    def initialize(path)
      super()
      @path = path
      @violations = []
    end

    def visit_call_node(node)
      construct = call_construct(node)
      record(node, construct) if construct
      super
    end

    def visit_def_node(node)
      record(node, "def #{node.name}") if DEFINITIONS.include?(node.name)
      super
    end

    def visit_constant_read_node(node)
      record(node, node.name.to_s) if CONSTANTS.include?(node.name)
      super
    end

    def visit_constant_path_node(node)
      record(node, node.name.to_s) if CONSTANTS.include?(node.name)
      super
    end

    private

    def call_construct(node)
      if COMPUTED_NAME_CALLS.include?(node.name)
        "#{node.name} with a computed name" unless literal_name?(node)
      elsif CALLS.include?(node.name)
        node.name.to_s
      elsif node.name == :binding && !node.receiver && !node.arguments
        "binding"
      end
    end

    def literal_name?(node)
      first = node.arguments&.arguments&.first
      first.is_a?(Prism::SymbolNode) || first.is_a?(Prism::StringNode)
    end

    def record(node, construct)
      @violations << Violation.new(@path, node.location.start_line, construct)
    end
  end
end
