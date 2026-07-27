module Crystallabs::Helpers
  VERSION = "1.0.1"

  module Logging
    macro included
      Log = ::Log.for self.name.gsub("::", '.').underscore
    end

    # Returns as a string the current method name and all arguments inspected.
    macro my(*args)
      String.build(128) {|%s|
        %s << {{@def.name.stringify}}
        %s << ':'
        {% for a in args %}
          %s << ' ' << {{a.stringify}} << '='
          ({{a}}).inspect %s
        {% end %}
      }
    end
  end

  module Boolean
    # The lowercase tokens that, ignoring surrounding whitespace and case, are
    # treated as `false`. Everything else non-blank is `true`.
    FALSY_TOKENS = {"false", "0", "no", "off", "f", "n", "-0", "0n"}

    # :nodoc:
    def to_b(arg : String, empty = false)
      return empty if arg.blank?
      # Fast path for pure-ASCII strings (the common case): strip/case-fold in
      # place over the byte buffer instead of allocating the two intermediate
      # strings `arg.strip.downcase` would. Equivalent for all-ASCII input;
      # non-ASCII falls back to the fully Unicode-correct path below.
      return ascii_to_b(arg.to_slice, empty) if arg.ascii_only?
      !FALSY_TOKENS.includes?(arg.strip.downcase)
    end

    private def ascii_to_b(bytes : Bytes, empty : Bool) : Bool
      lo = 0
      hi = bytes.size
      while lo < hi && bytes[lo].unsafe_chr.ascii_whitespace?
        lo += 1
      end
      while hi > lo && bytes[hi - 1].unsafe_chr.ascii_whitespace?
        hi -= 1
      end
      return empty if lo == hi
      FALSY_TOKENS.none? { |tok| ascii_falsy_match?(bytes, lo, hi - lo, tok) }
    end

    private def ascii_falsy_match?(bytes : Bytes, lo : Int32, len : Int32, tok : String) : Bool
      return false unless tok.bytesize == len
      token = tok.to_slice
      len.times do |i|
        byte = bytes[lo + i]
        byte |= 0x20_u8 if 0x41_u8 <= byte <= 0x5A_u8 # ASCII upper -> lower
        return false if byte != token[i]
      end
      true
    end

    # :nodoc:
    @[AlwaysInline]
    def to_b(arg : Int, empty = false)
      arg != 0
    end

    # :nodoc:
    def to_b(arg : Char, empty = false)
      # For an ASCII char, decide directly instead of allocating via `arg.to_s`.
      # Mirrors the `String` overload: ASCII-whitespace is blank (`empty`); the
      # single-char `FALSY_TOKENS` members are `'0'`, `'f'` and `'n'` (case-
      # insensitive), else `true`. Non-ASCII falls back to the string path.
      if arg.ascii?
        return empty if arg.ascii_whitespace?
        case arg
        when '0', 'f', 'F', 'n', 'N'
          return false
        end
        return true
      end
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
  # A "shorthand" is a `Symbol` or `String`, both going through `Enum.parse`.
  # Conversion is via the generic `from` class methods below, for any enum `T`.
  module Enums
    # An enum member referred to in shorthand, by `Symbol` or `String`.
    alias Shorthand = Symbol | String

    # The "shorthand side" of an enum-valued argument: a single shorthand, or a
    # collection of shorthands (for `@[Flags]` enums). One shared alias for every
    # enum. By convention the intended enum is listed first in the union, e.g.
    # `Tput::AlignFlag | Enums::Shorthands`.
    alias Shorthands = Shorthand | Enumerable(Shorthand)

    # Passthrough: a value already of the target enum is returned as-is, so call
    # sites accept both `:center` and `AlignFlag::Center` uniformly.
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

    # Converts a collection of shorthands into a combined enum value by OR-ing
    # the members together — for `@[Flags]` enums, e.g.
    # `Enums.from(AlignFlag, {:vcenter, :right}) # => VCenter | Right`.
    # Symbols and strings may be mixed. An empty collection yields the zero
    # value (e.g. `AlignFlag::None`).
    def self.from(t : T.class, values : Enumerable(Shorthand)) forall T
      # Delegates to the single-shorthand overload so the conversion logic
      # lives in one place.
      values.reduce(T.new(0)) { |acc, v| acc | from(T, v) }
    end

    # Declares an enum-typed `property` like the built-in macro, plus a setter
    # overload accepting a shorthand or collection of shorthands
    # (`Symbol`/`String`), so both the assignment form and any initializer
    # routing through `self.NAME = ...` accept shorthands transparently.
    #
    # The conversion target is derived from the property's own type via
    # `typeof`, so the enum is never named twice:
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
    # One forwarder is defined per overload of *old_method*, reproducing that
    # overload's parameter list verbatim — restrictions, defaults, keyword-only
    # section and block argument included. So the alias is exactly as type-safe
    # as what it aliases, and named arguments and blocks both work.
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
    # Copying the restrictions is what makes an alias safe to introduce next to
    # an *existing* method of the same name inherited from elsewhere. An
    # unrestricted `def alias(*args)` forwarder would sit closer in the ancestor
    # chain than that inherited method and silently swallow every call to it; a
    # restricted one only claims the argument types it actually handles, leaving
    # the rest to resolve as before.
    #
    # This macro was present in Crystal until commit 7c3239ee505e07544ec372839efed527801d210a.
    macro alias_method(new_method, old_method)
      {% if @type.methods.any? { |meth| meth.name.id == new_method.id } %}
        {% raise "Alias name '#{new_method.id}' already exists as a method!" %}
      {% end %}
      {% overloads = @type.methods.select { |meth| meth.name.id == old_method.id } %}
      {% if overloads.empty? %}
        {% raise "Cannot alias '#{new_method.id}' to '#{old_method.id}': no such method (yet) on #{@type}. Note the target must already be defined at this point." %}
      {% end %}
      {% for m in overloads %}
        {% params = [] of ::String %}
        {% fwd = [] of ::String %}
        {% for a, i in m.args %}
          {% bare_splat = i == m.splat_index && a.name.stringify.empty? %}
          {% decl = bare_splat ? "*" : "#{i == m.splat_index ? "*".id : "".id}#{a.name}" %}
          {% decl = "#{decl.id} : #{a.restriction}" if !a.restriction.is_a?(Nop) %}
          {% decl = "#{decl.id} = #{a.default_value}" if !a.default_value.is_a?(Nop) %}
          {% params << decl %}
          # A bare `*` only opens the keyword-only section — there is nothing to
          # forward for it. Everything after it must be passed *by name*.
          {% if !bare_splat %}
            {% if i == m.splat_index %}
              {% fwd << "*#{a.name}" %}
            {% elsif m.splat_index && i > m.splat_index %}
              {% fwd << "#{a.name}: #{a.name}" %}
            {% else %}
              {% fwd << "#{a.name}" %}
            {% end %}
          {% end %}
        {% end %}
        {% if m.double_splat %}
          {% params << "**#{m.double_splat.name}" %}
          {% fwd << "**#{m.double_splat.name}" %}
        {% end %}
        {% if m.block_arg %}
          {% b = "&#{m.block_arg.name}" %}
          {% b = "#{b.id} : #{m.block_arg.restriction}" if !m.block_arg.restriction.is_a?(Nop) %}
          {% params << b %}
          {% fwd << "&#{m.block_arg.name}" %}
        {% end %}
        # :nodoc:
        def {{new_method.id}}({{params.join(", ").id}})
          self.{{old_method.id}}({{fwd.join(", ").id}})
        end
      {% end %}
    end

    # Defines new_method as an alias of the immediately preceding method.
    #
    # NOTE: only use this when the preceding method has a **single** overload.
    # `@type.methods` does not preserve source order once a name is overloaded,
    # so "the last one" is not reliably the one written just above. Name the
    # target explicitly with `alias_method` in that case.
    macro alias_previous(*new_methods)
      {% m = @type.methods.last %}
      {% for new_method in new_methods %}
        alias_method {{new_method.id.symbolize}}, {{m.name.id.symbolize}}
      {% end %}
    end
  end

  # Filesystem helpers.
  module Files
    # Finds a file with name *target* inside toplevel directory *start*,
    # depth-first, skipping the virtual/system trees. Returns the full path or
    # `nil`. Unreadable directories and vanished entries are skipped, and a
    # symlinked directory is not descended into (no cycle risk).
    def self.find_file(start : String, target : String) : String?
      return if %w[/dev /sys /proc /net].includes?(start)

      files = begin
        Dir.children start
      rescue Exception
        [] of String
      end

      files.each do |file|
        full = File.join start, file

        return full if file == target

        stat = begin
          File.info full, follow_symlinks: false
        rescue Exception
          nil
        end

        # `stat` is `File::Info?` — the `rescue` above yields `nil` for a
        # dangling symlink, a races-away entry, or EACCES — so it must be
        # guarded before `directory?`/`symlink?`.
        if stat && stat.directory? && !stat.symlink?
          found = find_file full, target
          return found if found
        end
      end

      nil
    end
  end

  # Small formatting helpers.
  module Format
    # Formats a byte count with the largest binary unit that keeps it >= 1, so
    # small values stay in plain bytes (`842B`) and large ones shrink to
    # `KiB`/`MiB`/… with one decimal (`3.2KiB`).
    def self.humanize_bytes(bytes : Int) : String
      units = {"B", "KiB", "MiB", "GiB", "TiB", "PiB"}
      value = bytes.to_f
      unit = 0
      while value >= 1024 && unit < units.size - 1
        value /= 1024
        unit += 1
      end
      unit == 0 ? "#{bytes}#{units[0]}" : "%.1f%s" % {value, units[unit]}
    end

    # Truncates *str* to *len* characters, replacing the last kept character
    # with *marker* when cut (mutt/pine-style column truncation).
    def self.truncate(str : String, len : Int32, marker : Char = '~') : String
      return str if str.size <= len
      "#{str[0, len - 1]}#{marker}"
    end
  end

  # Byte-stream helpers.
  module Streams
    # Splits *carry* + *chunk* on the newline byte into complete lines,
    # stripping a trailing `\r` (CRLF streams), and returns the extracted lines
    # plus the leftover partial line to carry into the next call. Pure and
    # side-effect free — the building block for tailing an fd/pipe.
    def self.extract_lines(carry : Bytes, chunk : Bytes) : {Array(String), Bytes}
      buf = Bytes.new(carry.size + chunk.size)
      carry.copy_to(buf) unless carry.empty?
      chunk.copy_to(buf[carry.size, chunk.size]) unless chunk.empty?

      lines = [] of String
      start = 0
      buf.each_with_index do |byte, i|
        next unless byte == 0x0A_u8 # '\n'
        stop = i
        stop -= 1 if stop > start && buf[stop - 1] == 0x0D_u8 # trailing '\r'
        lines << String.new(buf[start, stop - start])
        start = i + 1
      end

      rem = buf.size - start
      new_carry = Bytes.new(rem)
      buf[start, rem].copy_to(new_carry) if rem > 0
      {lines, new_carry}
    end
  end

  # A size-bounded memoization cache: a `Hash` that evicts entries once it
  # grows past *capacity*.
  #
  # Drop-in for a plain `Hash` used as a memo (`[]`, `[]?`, `[]=`, `has_key?`,
  # `delete`, `clear`, `fetch`), with two additions:
  #
  # * **Eviction.** When adding an entry would exceed *capacity*, the oldest
  #   entry is dropped (FIFO by default; strict LRU with `lru: true`). A
  #   *capacity* of `0` or less means unbounded.
  # * **Memoizing `fetch`.** `fetch(key) { compute }` stores and returns the
  #   computed value on a miss (and correctly caches a `nil` value, so it works
  #   for negative caching). This differs from `Hash#fetch`, which does *not*
  #   store.
  #
  # FIFO is the default because it keeps reads as pure `Hash` lookups, with no
  # reordering. Pass `lru: true` when recency-of-use should decide what survives
  # (e.g. an image decode cache) and the read cost is affordable.
  #
  # Not thread-safe.
  class BoundedCache(K, V)
    # Maximum entries kept; `<= 0` means unbounded.
    property capacity : Int32

    # Creates a cache holding at most *capacity* entries. *lru* switches
    # eviction from FIFO to least-recently-used. *by_identity* keys the cache
    # on object identity (`same?`) instead of value equality — for caches
    # memoizing per-object results, mirroring `Hash#compare_by_identity`.
    def initialize(@capacity : Int32, *, @lru : Bool = false, by_identity : Bool = false)
      @store = {} of K => V
      @store.compare_by_identity if by_identity
    end

    # Current number of entries.
    def size : Int32
      @store.size
    end

    # Whether *key* is present (distinguishes a cached `nil` value from absence).
    def has_key?(key : K) : Bool
      @store.has_key? key
    end

    # The value for *key*, or `nil` if absent. In `lru` mode a hit is promoted
    # to most-recently-used.
    def []?(key : K) : V?
      # FIFO has no reorder-on-read, and an absent key and a cached `nil` both
      # return `nil`, so one `[]?` is observably identical to `has_key?` +
      # `touch` at half the lookups. LRU must promote on a hit — and so must
      # tell a cached `nil` from absence — and keeps the two-step path.
      if @lru
        return unless @store.has_key? key
        touch key
      else
        @store[key]?
      end
    end

    # The value for *key*; raises `KeyError` if absent (like `Hash#[]`).
    def [](key : K) : V
      # As in `[]?`: FIFO needs no reorder-on-read, so a single `Hash#fetch`
      # with a raising block does one lookup where `has_key?` + `touch` does
      # two — and still tells a cached `nil` from absence. LRU must promote on
      # a hit and keeps the two-step path.
      if @lru
        raise KeyError.new("Missing cache key: #{key.inspect}") unless @store.has_key? key
        touch key
      else
        @store.fetch(key) { raise KeyError.new("Missing cache key: #{key.inspect}") }
      end
    end

    # Stores *value* under *key* and returns it, evicting if over capacity.
    def []=(key : K, value : V) : V
      @store[key] = value
      evict!
      value
    end

    # Returns the cached value for *key*, or computes it via the block, stores
    # it, and returns it. The block's result is cached even when `nil`.
    def fetch(key : K, & : -> V) : V
      # Same FIFO-vs-LRU split as `[]?`: `Hash#fetch(key, &)` resolves a hit in
      # one lookup and, unlike `@store[key]?`, still distinguishes a cached
      # `nil` value from an absent key — which is what makes negative caching
      # work. LRU promotes on a hit and so keeps `has_key?` + `touch`.
      if @lru
        @store.has_key?(key) ? touch(key) : (self[key] = yield)
      else
        @store.fetch(key) { self[key] = yield }
      end
    end

    # Removes *key*, returning its value or `nil`.
    def delete(key : K) : V?
      @store.delete key
    end

    # Empties the cache.
    def clear : Nil
      @store.clear
    end

    # Yields each `{key, value}` pair (insertion order).
    def each(& : Tuple(K, V) -> _) : Nil
      @store.each { |k, v| yield({k, v}) }
    end

    # Reads *key*'s value, promoting it in `lru` mode. Caller guarantees the
    # key is present.
    private def touch(key : K) : V
      value = @store[key]
      if @lru
        @store.delete key
        @store[key] = value
      end
      value
    end

    # Drops oldest entries until within capacity.
    private def evict! : Nil
      return unless @capacity > 0
      while @store.size > @capacity
        oldest = @store.first_key?
        break if oldest.nil?
        @store.delete oldest
      end
    end
  end

  # An emacs/readline-style kill ring: the shared text register that readline
  # editing keys push deleted text into (`Ctrl-W` / `Ctrl-U` / `Ctrl-K` /
  # `Alt-D`) and `Ctrl-Y` yanks back.
  #
  # As in emacs, consecutive kills accumulate into one entry (so `Ctrl-K Ctrl-K`
  # yanks both lines, and a backward kill prepends) until a non-kill action calls
  # `#interrupt`. Older entries are retained up to `#capacity` for a future
  # yank-pop.
  class KillRing
    # Shared default ring (all inputs of a program, unless overridden).
    class_property default : KillRing { KillRing.new }

    # Kill entries, oldest first; the last is what `#yank` returns.
    getter entries = [] of String

    # Maximum number of entries kept (older ones are dropped).
    property capacity : Int32

    # Whether the previous editing action was a kill, so the next consecutive
    # kill merges into the same entry rather than starting a new one.
    @last_was_kill = false

    def initialize(@capacity : Int32 = 60)
    end

    # Records *text* as a kill. A backward kill (*prepend* true — `Ctrl-W` /
    # `Ctrl-U`) joins the front of the current entry; a forward kill (*prepend*
    # false — `Ctrl-K` / `Alt-D`) joins the back. Consecutive kills merge; an
    # intervening `#interrupt` starts a fresh entry. Empty text is ignored.
    def kill(text : String, *, prepend : Bool = false) : Nil
      return if text.empty?
      if @last_was_kill && (last = @entries.last?)
        @entries[-1] = prepend ? text + last : last + text
      else
        @entries << text
        while @entries.size > @capacity
          @entries.shift
        end
      end
      @last_was_kill = true
    end

    # The most-recently killed text (what `Ctrl-Y` yanks), or `nil` when empty.
    def yank : String?
      @entries.last?
    end

    # Marks that a non-kill action happened, so the next kill starts a new entry.
    def interrupt : Nil
      @last_was_kill = false
    end

    # Drops all entries (and resets the accumulation flag).
    def clear : Nil
      @entries.clear
      @last_was_kill = false
    end
  end

  # An O(1) running average over the last *capacity* values pushed into it.
  #
  # Wraps a deque rather than subclassing `Deque(Int32)`: subclassing a stdlib
  # generic is deprecated and promotes every `Deque(Int32)` in the program
  # (including unrelated shards) to the virtual type `Deque(Int32)+`, causing
  # confusing compile errors elsewhere.
  class RunningAverage
    def initialize(@capacity : Int32)
      @deque = Deque(Int32).new @capacity
      # Running sum, kept in sync on every push/shift so `avg` is O(1)
      # instead of re-summing each call. `Int64` because pushed values can be
      # as large as `Int32::MAX`, and `capacity` of them would overflow an
      # `Int32` sum.
      @sum = 0_i64
    end

    # Pushes *value* and returns the average over the retained window.
    def avg(value : Int32) : Int64
      if @deque.size == @capacity
        @sum -= @deque.shift
      end
      @deque.push value
      @sum += value
      @sum // @deque.size
    end
  end
end
