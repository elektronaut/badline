# frozen_string_literal: true

require "spec_helper"
require_relative "support/spinel_subset"

# Keeps lib/badline inside the Ruby subset Spinel compiles, so the core
# stays compilable to C.
describe SpinelSubset do
  def scan(source)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "code.rb"), source)
      described_class.scan([File.join(dir, "code.rb")], root: dir).map(&:to_s)
    end
  end

  describe "lib/badline" do
    let(:root) { File.expand_path("..", __dir__) }
    let(:violations) { described_class.scan(Dir.glob(File.join(root, "lib/badline/**/*.rb")), root:) }

    it "stays inside Spinel's subset" do
      outside = violations.reject { |v| described_class.allowed?(v) }
      expect(outside).to be_empty, "Outside Spinel's subset:\n#{outside.join("\n")}"
    end

    it "uses every allowlist entry" do
      stale = described_class::ALLOWED - violations.map { |v| [v.path, v.construct] }
      expect(stale).to be_empty, "No longer needed, remove from SpinelSubset::ALLOWED: #{stale}"
    end
  end

  describe ".scan" do
    it "names the file, line and construct" do
      expect(scan("x = 1\nsend(name)\n")).to eq(["code.rb:2: send with a computed name"])
    end

    it "flags public_send and __send__ with a computed name" do
      expect(scan("obj.public_send(n)\n__send__(n)"))
        .to eq(["code.rb:1: public_send with a computed name", "code.rb:2: __send__ with a computed name"])
    end

    it "allows send and const_get with a literal name" do
      expect(scan("send(:reset); const_get(\"Foo\")")).to be_empty
    end

    it "flags const_get and const_set with a computed name" do
      expect(scan("const_get(n)\nObject.const_set(n, 1)"))
        .to eq(["code.rb:1: const_get with a computed name", "code.rb:2: const_set with a computed name"])
    end

    it "flags code evaluation" do
      expect(scan("eval(s); A.class_eval(s); a.instance_eval {}; A.module_eval(s)"))
        .to eq(%w[eval class_eval instance_eval module_eval].map { |c| "code.rb:1: #{c}" })
    end

    it "flags method definition at runtime" do
      expect(scan("define_method(:a) {}; a.define_singleton_method(:b) {}"))
        .to eq(%w[define_method define_singleton_method].map { |c| "code.rb:1: #{c}" })
    end

    it "flags method_missing and respond_to_missing?" do
      expect(scan("def method_missing(*) = nil\ndef respond_to_missing?(*) = true"))
        .to eq(["code.rb:1: def method_missing", "code.rb:2: def respond_to_missing?"])
    end

    it "flags Forwardable and its delegators" do
      expect(scan("extend ::Forwardable; def_delegator :@a, :b; def_delegators :@a, :c"))
        .to eq(%w[Forwardable def_delegator def_delegators].map { |c| "code.rb:1: #{c}" })
    end

    it "flags instance variable reflection" do
      expect(scan("instance_variable_get(:@a); instance_variable_set(:@a, 1)"))
        .to eq(%w[instance_variable_get instance_variable_set].map { |c| "code.rb:1: #{c}" })
    end

    it "flags ObjectSpace and binding" do
      expect(scan("ObjectSpace.each_object {}; binding"))
        .to eq(%w[ObjectSpace binding].map { |c| "code.rb:1: #{c}" })
    end

    it "leaves a binding method on an object alone" do
      expect(scan("gamepad.binding")).to be_empty
    end
  end
end
