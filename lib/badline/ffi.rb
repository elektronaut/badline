# frozen_string_literal: true

require "fiddle"

module Badline
  # The part of Spinel's FFI DSL the SDL binding uses, for CRuby, over
  # Fiddle, so the one binding in badline/sdl serves both builds. Spinel
  # compiles the declarations itself and never loads this file: require it
  # before a file that declares a binding.
  #
  # The declarations behave as they do in Spinel. ffi_func defines
  # Module.name(...); a pointer argument takes nil for NULL, a Fiddle
  # pointer, a String (its bytes) or an IO::Buffer, whose contents C sees
  # for the call's duration; a NULL pointer comes back as nil. ffi_const
  # sets Module::NAME, ffi_buffer defines Module.name returning a zeroed
  # static buffer, and ffi_read_<width> and ffi_write_<width> define field
  # accessors at a fixed offset into a pointer.
  module FFI
    class Error < StandardError; end

    TYPES = {
      void: Fiddle::TYPE_VOID,
      int: Fiddle::TYPE_INT, bool: Fiddle::TYPE_INT, long: Fiddle::TYPE_LONG, size_t: Fiddle::TYPE_SIZE_T,
      int8: Fiddle::TYPE_INT8_T, uint8: Fiddle::TYPE_UINT8_T, int16: Fiddle::TYPE_INT16_T,
      uint16: Fiddle::TYPE_UINT16_T, int32: Fiddle::TYPE_INT32_T, uint32: Fiddle::TYPE_UINT32_T,
      float: Fiddle::TYPE_FLOAT, double: Fiddle::TYPE_DOUBLE,
      str: Fiddle::TYPE_CONST_STRING,
      ptr: Fiddle::TYPE_VOIDP, buffer_in: Fiddle::TYPE_VOIDP, buffer_out: Fiddle::TYPE_VOIDP,
      buffer_inout: Fiddle::TYPE_VOIDP, int_array: Fiddle::TYPE_VOIDP, float_array: Fiddle::TYPE_VOIDP
    }.freeze

    # The argument specs C may write through, so an IO::Buffer passed in one
    # gets back what C left in it.
    WRITABLE = %i[ptr buffer_out buffer_inout].freeze

    # pack directives for the accessor widths, in the host's byte order.
    WIDTHS = {
      u8: "C", i8: "c", u16: "S", i16: "s", u32: "L", i32: "l", u64: "Q", i64: "q", ptr: "J"
    }.freeze

    # Where dlopen looks for a library besides its search path, which leaves
    # out Homebrew's, and the versioned names a runtime package installs
    # without the development package's unversioned link.
    DIRECTORIES = [nil, "/opt/homebrew/lib", "/usr/local/lib"].freeze
    VERSIONED = { "SDL2" => %w[libSDL2-2.0.so.0 libSDL2-2.0.0.dylib] }.freeze

    module_function

    def open_library(name)
      candidates = library_candidates(name)
      candidates.each do |candidate|
        return Fiddle.dlopen(candidate)
      rescue Fiddle::DLError
        next
      end
      raise Error, "can't find lib#{name} (tried #{candidates.join(', ')})"
    end

    def library_candidates(name)
      names = ["lib#{name}.dylib", "lib#{name}.so", *VERSIONED.fetch(name, []), "#{name}.dll"]
      DIRECTORIES.flat_map { |dir| names.map { |file| dir ? File.join(dir, file) : file } }
    end

    # The value Fiddle passes for one argument, and a block that copies what
    # C wrote back into an IO::Buffer once the call returns.
    def argument(spec, value)
      case value
      when IO::Buffer then buffer_argument(spec, value)
      when Array then [value.pack(spec == :float_array ? "d*" : "q*")]
      when true, false then [value ? 1 : 0]
      else [value]
      end
    end

    def buffer_argument(spec, buffer)
      return [nil] if buffer.null? || buffer.empty?

      bytes = buffer.get_string
      return [bytes] unless WRITABLE.include?(spec) && !buffer.readonly?

      [bytes, -> { buffer.set_string(bytes) }]
    end

    def result(spec, value)
      case spec
      when :ptr then value.null? ? nil : value
      when :bool then value != 0
      else value
      end
    end

    def read(pointer, offset, width)
      value = Fiddle::Pointer[pointer][offset, width_size(width)].unpack1(WIDTHS.fetch(width))
      width == :ptr ? result(:ptr, Fiddle::Pointer.new(value)) : value
    end

    def write(pointer, offset, width, value)
      value = value.to_i if width == :ptr
      Fiddle::Pointer[pointer][offset, width_size(width)] = [value || 0].pack(WIDTHS.fetch(width))
      value
    end

    def width_size(width) = [0].pack(WIDTHS.fetch(width)).bytesize

    # The declarations, private methods of every module once this file is
    # loaded, as they are keywords of a module body in Spinel.
    module DSL
      private

      def ffi_lib(name)
        (@ffi_libraries ||= []) << FFI.open_library(name)
      end

      def ffi_func(name, arguments, returns, blocking: false)
        function = Fiddle::Function.new(ffi_symbol(name), arguments.map { |spec| TYPES.fetch(spec) },
                                        TYPES.fetch(returns), name: name.to_s, need_gvl: !blocking)
        define_singleton_method(name) do |*values|
          converted = arguments.zip(values).map { |spec, value| FFI.argument(spec, value) }
          returned = function.call(*converted.map(&:first))
          converted.each { |argument| argument[1]&.call }
          FFI.result(returns, returned)
        end
      end

      def ffi_const(name, value)
        const_set(name, value)
      end

      def ffi_buffer(name, size)
        buffer = Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE)
        buffer[0, size] = "\0" * size
        define_singleton_method(name) { buffer }
      end

      WIDTHS.each_key do |width|
        define_method(:"ffi_read_#{width}") do |name, offset|
          define_singleton_method(name) { |pointer| FFI.read(pointer, offset, width) }
        end

        define_method(:"ffi_write_#{width}") do |name, offset|
          define_singleton_method(name) { |pointer, value| FFI.write(pointer, offset, width, value) }
        end
      end

      def ffi_symbol(name)
        (@ffi_libraries || []).each do |library|
          return library[name.to_s]
        rescue Fiddle::DLError
          next
        end
        Fiddle::Handle::DEFAULT[name.to_s]
      end
    end
  end
end

Module.include(Badline::FFI::DSL)
