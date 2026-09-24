# frozen_string_literal: true

# The JIT a bin/ tool runs under, so the processes it spawns run under the
# same one: --zjit, --yjit, or none on TruffleRuby, which has no RubyVM
# and takes no flag.
module Jit
  module_function

  def yjit? = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  def zjit? = defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?

  def flags
    return ["--zjit"] if zjit?
    return ["--yjit"] if yjit?

    []
  end

  # Turns YJIT on in a CRuby started without a JIT flag.
  def enable
    RubyVM::YJIT.enable if defined?(RubyVM::YJIT) && !yjit? && !zjit?
  end
end
