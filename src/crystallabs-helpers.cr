module Crystallabs::Helpers
  VERSION = "0.1.0"

  module Logging
    macro included
      Log = ::Log.for self.name
    end
  end

  module Boolean

    # :nodoc:
    def to_b(arg : String, empty = false)
      return empty if !empty.nil? && (arg.nil? || arg.empty?)
      return false if {"false", "", "0", "-0", "0n", " "}.includes? arg
      true
    end

    # :nodoc:
    def to_b(arg : Int, empty = false)
      arg != 0
    end

    # :nodoc:
    def to_b(arg : Char, empty = false)
      to_b arg.to_s
    end

    def to_b(arg : Nil, empty = false)
      false
    end

    def to_b(arg : Bool)
      arg
    end

    def to_i(arg : Bool)
      arg ? 1 : 0
    end
  end

  module File
    # TODO try_read(Str | Arr), return first found, else ''
  end

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
    # person.name #=> "John"
    # person.full_name #=> "John"
    # ```
    #
    # This macro was present in Crystal until commit 7c3239ee505e07544ec372839efed527801d210a.
    macro alias_method(new_method, old_method)
      def {{new_method.id}}(*args)
        {{old_method.id}}(*args)
      end
    end

    # Defines new_method as an alias of last (most recently defined) method.
    # TODO add check to catch multiple aliases to the same name
    macro alias_previous(*new_methods)
      {% for new_method in new_methods %}
        alias_method {{new_method}}, {{@type.methods.last.name}}
      {% end %}
    end
  end

end
