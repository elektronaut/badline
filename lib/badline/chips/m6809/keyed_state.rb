# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      # Every plan the CPU runs and every tail it keeps, by the name a
      # snapshot gives it: the plans of their own by name, an indexed
      # postbyte's, a PSH's and a PUL's by postbyte, and an opcode's by its
      # page and opcode. A plan that has several names goes by the first.
      module PlanNames
        OWN = { "fetch" => FETCH_PLAN, "reset" => RESET_PLAN, "prefix" => PREFIX_PLAN, "none" => NO_TAIL,
                "jump" => JUMP_TAIL, "interrupt" => INTERRUPT_PLAN, "fast_interrupt" => FAST_INTERRUPT_PLAN,
                "waited_interrupt" => WAITED_INTERRUPT_PLAN, "return_entire" => RETURN_ENTIRE_PLAN,
                "return_fast" => RETURN_FAST_PLAN, "long_branch_taken" => LONG_BRANCH_TAKEN_PLAN,
                "sync_end" => SYNC_END_PLAN }.freeze

        PAGES = [PAGE1, PAGE2, PAGE3].freeze

        TABLE = (OWN.to_a +
                 { "indexed" => INDEXED_PLANS, "push" => PUSH_PLANS, "pull" => PULL_PLANS }.flat_map do |kind, plans|
                   Array.new(256) { |post| ["#{kind}.#{post}", plans[post]] }
                 end +
                 Array.new(PAGES.length * 256) do |slot|
                   entry = PAGES[slot >> 8][slot & 0xff]
                   name = "op.#{(slot >> 8) + 1}.#{slot & 0xff}"
                   [["#{name}.plan", entry.plan], ["#{name}.tail", entry.tail]]
                 end.flatten(1)).freeze

        NAMES = TABLE.map(&:first).freeze
        PLANS = TABLE.map(&:last).freeze

        # What the opcodes and the interrupts run, by name.
        OPERATIONS = (%w[none enter_nmi enter_firq enter_irq] +
                      PAGES.flat_map { |page| page.map { |entry| entry.operation.to_s } }).uniq.freeze

        module_function

        def name_of(plan)
          index = PLANS.index { |each_plan| each_plan.equal?(plan) }
          index.nil? ? "fetch" : NAMES[index]
        end

        def named(name)
          index = NAMES.index(name)
          index.nil? ? nil : PLANS[index]
        end
      end

      # The CPU's fields in a keyed snapshot module (Snapshot::Keyed): the
      # registers, the interrupt lines and what the CPU has sampled of
      # them, the cycle count, the working registers the steps share, and
      # off an instruction boundary the plan running, the step in it and
      # the tail to follow, by PlanNames. A plan it doesn't know puts the
      # CPU on a boundary.
      module KeyedState
        def save_fields(out)
          out.int("a", @a).int("b", @b).int("x", @x).int("y", @y).int("u", @u).int("s", @s).int("pc", @pc)
          out.int("dp", @dp).int("cc", @cc).int("cycles", @cycles)
          out.bool("irq", @irq).bool("firq", @firq).bool("nmi", @nmi).bool("halt", @halt)
          out.bool("irq.latched", @irq_latched).bool("irq.seen", @irq_seen)
          out.bool("firq.latched", @firq_latched).bool("firq.seen", @firq_seen)
          out.bool("nmi.edge", @nmi_edge).bool("nmi.latched", @nmi_latched).bool("nmi.seen", @nmi_seen)
          out.bool("nmi.armed", @nmi_armed).bool("halt.latched", @halt_latched).bool("halt.seen", @halt_seen)
          save_working_fields(out)
          out
        end

        def load_fields(input)
          load_registers(input)
          load_lines(input)
          load_working_fields(input)
        end

        def restored! = nil

        private

        def save_working_fields(out)
          out.int("ea", @ea).int("value", @value).int("post", @post).int("opcode", @opcode)
          out.text("operation", @operation.to_s).int("page", PlanNames::PAGES.index { |page| page.equal?(@page) } + 1)
          out.int("group", @group).int("previous_group", @previous_group).int("alu_word", @alu_word)
          out.int("vector", @vector).int("interrupt_mask", @interrupt_mask).bool("stack_u", @stack_u)
          return if boundary?

          out.text("pos.plan", PlanNames.name_of(@plan)).int("pos.index", @index)
          out.text("pos.tail", PlanNames.name_of(@tail))
        end

        def load_registers(input)
          @a = input.byte("a", @a)
          @b = input.byte("b", @b)
          @x = input.word("x", @x)
          @y = input.word("y", @y)
          @u = input.word("u", @u)
          @s = input.word("s", @s)
          @pc = input.word("pc", @pc)
          @dp = input.byte("dp", @dp)
          @cc = input.byte("cc", @cc)
          @cycles = input.int("cycles", @cycles)
        end

        def load_lines(input)
          @irq = input.bool("irq", false)
          @firq = input.bool("firq", false)
          @nmi = input.bool("nmi", false)
          @halt = input.bool("halt", false)
          @irq_latched = input.bool("irq.latched", false)
          @irq_seen = input.bool("irq.seen", false)
          @firq_latched = input.bool("firq.latched", false)
          @firq_seen = input.bool("firq.seen", false)
          @nmi_edge = input.bool("nmi.edge", false)
          @nmi_latched = input.bool("nmi.latched", false)
          @nmi_seen = input.bool("nmi.seen", false)
          @nmi_armed = input.bool("nmi.armed", @nmi_armed)
          @halt_latched = input.bool("halt.latched", false)
          @halt_seen = input.bool("halt.seen", false)
        end

        def load_working_fields(input)
          @ea = input.word("ea", 0)
          @value = input.word("value", 0)
          @post = input.byte("post", 0)
          @opcode = input.byte("opcode", 0)
          @operation = input.choice("operation", PlanNames::OPERATIONS, "none").to_sym
          @page = PlanNames::PAGES.fetch(input.int("page", 1).clamp(1, 3) - 1)
          @group = input.int("group", GROUP_OTHER)
          @previous_group = input.int("previous_group", GROUP_OTHER)
          @alu_word = input.int("alu_word", 0)
          @vector = input.word("vector", 0xfffe)
          @interrupt_mask = input.byte("interrupt_mask", 0)
          @stack_u = input.bool("stack_u", false)
          load_position(input)
        end

        def load_position(input)
          plan = PlanNames.named(input.text("pos.plan", "fetch"))
          tail = PlanNames.named(input.text("pos.tail", "none"))
          return boundary if plan.nil? || tail.nil? || plan.empty?

          @plan = plan
          @index = input.int("pos.index", 0).clamp(0, plan.length - 1)
          @tail = tail
        end
      end
    end
  end
end
