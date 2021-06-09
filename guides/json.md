# JSON Support

Support for JSON serialization is built upon `Ecto.embedded_dump/2`, but must be explicitly enabled. This is to allow
you to provide your own implementation if you don't desire to use the generated one. However, deriving the
encoder is dead simple, and looks just like it would for any old struct. For example:

    # defstruct/1
    defmodule Person do
      @derives [Jason.Encoder]
      defstruct do
        field :name, :string

        timestamps()
      end
    end

    # defstruct/2
    defstruct Person do
      @derives [Jason.Encoder]

      field :name, :string

      timestamps()
    end

Internally, `defstruct` provides a concrete implementation of `Jason.Encoder` that calls out to `Ecto.embedded_dump/2`.
For deserialization, `from_json/1` is defined for the struct's module, and uses `Ecto.embedded_load/3` to deserialize 
back to the original struct using the canonical deserializer for each field type.

The difference versus just letting `@derives [Jason.Encoder]` do its thing, is that `embedded_dump/2` and `embedded_load/3`
ensure that the types are dumped/loaded according to their respective Ecto type definitions, which should produce canonical
JSON encodings, as opposed to naively encoding fields based on their raw Elixir representation.

NOTE: Currently, we only implement special support for `Jason.Encoder`, if you use another JSON library, it
is recommended that you implement the relevant encoder yourself using `Ecto.embedded_dump/2`, much like we do
for our implementation of `Jason.Encoder`.
