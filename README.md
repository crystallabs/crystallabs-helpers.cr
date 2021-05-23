# Crystallabs-helpers

Collection of useful helper modules.

There is no disadvantage to using this shard in projects that only
require part of its functionality. Crystal does not include unused
functions in the resulting binary.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     crystallabs-helpers:
       github: crystallabs/crystallabs-helpers.cr
       version: ~> 1.0
   ```

2. Run `shards install`

## Usage

Helper functionality is split by modules. Include the modules where you
need them:

### Crystallabs::Helpers::Logging

```cr
    macro included
      Log = ::Log.for self.name.gsub("::", '.').underscore
    end

    # Returns as a string the current method name and all arguments inspected.
    macro my(*args, line=__LINE__)
    end
```

Usage:

```cr
  # Automatically prefixes log lines with self' name
  Log.debug { ... }

  # Log object/variable values inspected
  Log.debug { my varx, vary, ... }
```

### Crystallabs::Helpers::Boolean

```cr
    def to_b(arg : String, empty = false)
    def to_b(arg : Int, empty = false)
    def to_b(arg : Char, empty = false)
    def to_b(arg : Nil, empty = false)
    def to_b(arg : Bool)

    def to_i(arg : Bool)
```

Usage:

```cr
  to_b "0"
  to_b 1
  to_b '0'
  to_b nil

  to_i true
```

### Crystallabs::Helpers::Alias_Methods

Allows aliasing methods. Use only when needed since in general Crystal
ecosystem does not prefer aliases.

```cr
    macro alias_method(new_method, old_method)
    macro alias_previous(*new_methods)
```

Usage:

```cr
  alias_method new_method_name, existing_method_name
  alias_method :new_method_name=, :existing_method_name=

  def mymethod
  end
  alias_previous new_name
```
