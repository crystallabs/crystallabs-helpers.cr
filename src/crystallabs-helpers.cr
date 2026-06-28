module Crystallabs::Helpers
  VERSION = "1.0.1"

  module Logging
    macro included
      Log = ::Log.for self.name.gsub("::", '.').underscore
    end

    # Returns as a string the current method name and all arguments inspected.
    macro my(*args, line = __LINE__)
      String.build(128) {|__s|
        __s << {{@def.name.stringify}}
        __s << ':' #<< {{line}} << ':'
        {% for a in args %}
          __s << ' ' << {{a.stringify}} << '='
          {{a}}.inspect __s
        {% end %}
      }
    end
  end

  module Boolean
    # :nodoc:
    def to_b(arg : String, empty = false)
      return empty if arg.blank?
      return false if {"false", "0", "-0", "0n"}.includes? arg.strip.downcase
      true
    end

    # :nodoc:
    @[AlwaysInline]
    def to_b(arg : Int, empty = false)
      arg != 0
    end

    # :nodoc:
    def to_b(arg : Char, empty = false)
      to_b arg.to_s, empty
    end

    @[AlwaysInline]
    def to_b(arg : Nil, empty = false)
      empty
    end

    @[AlwaysInline]
    def to_b(arg : Bool, empty = false)
      arg
    end

    @[AlwaysInline]
    def to_i(arg : Bool)
      arg ? 1 : 0
    end
  end

  # Helpers for working with enums via plain shorthands, so callers can write
  # `:vcenter` / `"vcenter"` (or `{:vcenter, :right}`) instead of
  # `Tput::AlignFlag::VCenter` (or `Tput::AlignFlag::VCenter | Tput::AlignFlag::Right`).
  #
  # A "shorthand" is a `Symbol` or a `String` — both go through `Enum.parse`, so
  # the two are interchangeable everywhere below.
  #
  # Nothing in the standard library is reopened; conversion is done through the
  # generic `from` class methods below, which work for any enum `T`.
  module Enums
    # An enum member referred to in shorthand, by `Symbol` or `String`.
    alias Shorthand = Symbol | String

    # The "shorthand side" of an enum-valued argument: a single shorthand, or a
    # collection of shorthands (for `@[Flags]` enums). One shared alias for every
    # enum — no per-enum aliases needed. By convention the intended enum is listed
    # *first* in the union, e.g. `Tput::AlignFlag | Enums::Shorthands`.
    alias Shorthands = Shorthand | Enumerable(Shorthand)

    # Passthrough: a value that is already of the target enum is returned as-is.
    # Lets call sites accept both `:center` and `AlignFlag::Center` uniformly.
    @[AlwaysInline]
    def self.from(t : T.class, value : T) forall T
      value
    end

    # Converts a single shorthand (symbol or string) into an enum member, e.g.
    # `Enums.from(AlignFlag, :center)` or `Enums.from(AlignFlag, "center")`,
    # both `# => AlignFlag::Center`. Matching is case-insensitive (`Enum.parse`).
    def self.from(t : T.class, value : Shorthand) forall T
      T.parse value.to_s
    end

    # Converts a collection of shorthands into a combined enum value by OR-ing the
    # members together — intended for `@[Flags]` enums, e.g.
    # `Enums.from(AlignFlag, {:vcenter, :right}) # => VCenter | Right`.
    # Symbols and strings may be mixed. An empty collection yields the zero
    # value (e.g. `AlignFlag::None`).
    def self.from(t : T.class, values : Enumerable(Shorthand)) forall T
      # Delegate each element to the single-shorthand overload above so the
      # shorthand-to-member conversion lives in exactly one place and the two
      # paths can't drift apart.
      values.reduce(T.new(0)) { |acc, v| acc | from(T, v) }
    end

    # Declares an enum-typed `property` exactly like the built-in macro, and in
    # addition defines a setter overload that accepts a shorthand or collection
    # of shorthands (`Symbol`/`String`). After this, both the assignment form and
    # any initializer that routes its argument through `self.NAME = ...` accept
    # shorthands transparently.
    #
    # The conversion target is derived from the property's own type via
    # `typeof`, so the enum is never named twice and the setter stays generic:
    #
    # ```
    # class Widget
    #   Crystallabs::Helpers::Enums.enum_property align : Tput::AlignFlag = Tput::AlignFlag::Top | Tput::AlignFlag::Left
    #
    #   # In a hand-written initializer, widen the argument and route it through
    #   # the setter; the enum is listed first, followed by the shared `Shorthands`:
    #   def initialize(align : Tput::AlignFlag | Crystallabs::Helpers::Enums::Shorthands = @align)
    #     self.align = align
    #   end
    # end
    #
    # w.align = :center            # => Center
    # w.align = "center"           # => Center
    # w.align = {:vcenter, :right} # => VCenter | Right
    # w.align = Tput::AlignFlag::Left
    # ```
    macro enum_property(decl)
      property {{decl.var.id}} : {{decl.type}}{% if decl.value %} = {{decl.value}}{% end %}

      def {{decl.var.id}}=(value : ::Crystallabs::Helpers::Enums::Shorthands)
        @{{decl.var.id}} = ::Crystallabs::Helpers::Enums.from(typeof(@{{decl.var.id}}), value)
      end
    end
  end

  # ameba:disable Naming/TypeNames -- deliberate public API name (released, snake_case mirrors `alias_method`)
  module Alias_Methods
    # Defines new_method as an alias of old_method.
    #
    # This creates a new method new_method that invokes old_method.
    #
    # Note that due to current language limitations this is only useful
    # when neither named arguments nor blocks are involved.
    #
    # ```
    # class Person
    #   getter name
    #
    #   def initialize(@name)
    #   end
    #
    #   alias_method full_name, name
    # end
    #
    # person = Person.new "John"
    # person.name      # => "John"
    # person.full_name # => "John"
    # ```
    #
    # This macro was present in Crystal until commit 7c3239ee505e07544ec372839efed527801d210a.
    macro alias_method(new_method, old_method)
      {% if @type.methods.any? { |meth| meth.name.id == new_method.id } %}
        {% raise "Alias name '#{new_method.id}' already exists as a method!" %}
      {% end %}
      # A setter (`name=`) forwards its single assigned value; any other method
      # forwards all positional arguments. (A setter cannot take a splat.) The
      # decision is computed once so the signature and the call can't drift apart.
      {% setter = old_method.id.ends_with? "=" %}
      # :nodoc:
      def {{new_method.id}}({% if setter %}arg{% else %}*args{% end %})
        self.{{old_method.id}}({% if setter %}arg{% else %}*args{% end %})
      end
    end

    # Defines new_method as an alias of last (most recently defined) method.
    macro alias_previous(*new_methods)
      {% m = @type.methods.last %}
      {% for new_method in new_methods %}
        alias_method {{new_method.id.symbolize}}, {{m.name.id.symbolize}}
      {% end %}
    end
  end
end
