# Usage

This document details further how Strukt is implemented, and how to use it. Please report any issues on the issue tracker.

### Struct Definition

There are two variants, depending on how you want to define your structs, `Strukt.defstruct/1` and `Strukt.defstruct/2`.

The first is used to define a struct associated with the current module being defined:

    defmodule Person do
      use Strukt

      defstruct do
        field :name, :string, required: true
      end

      def name(person), do: person.name
    end

The second is used to define a struct _and_ its module, inline:

    defmodule Entities do
      use Strukt

      defstruct Person do
        field :name, :string, required: true

        def name(person), do: person.name
      end
    end

The latter is generally useful only when you want to define multiple modules in the same file, which is
probably relatively rare, but comes up from time to time, and this reduces the boilerplate a bit.

Lastly, it is worth noting that embedded structs behave almost identically to `Strukt.defstruct/2`:

    defmodule Company do
      use Strukt

      defstruct do
        field :name, :string, required: true

        embeds_many :employees, Employee do
          field :name, :string, required: true
          field :email, :string, required: true, format: ~r/^.+@.+$/

          def name(employee), do: employee.name
        end
      end
    end

In the above, you'd end up with two modules, `Company` and `Company.Employee`. It's generally recommended to
split up the definition of embedded structs, but in simple cases where the embedded type is strictly used only
within the context of the containing type, it may be easier to keep the definitions together like this.

### Working with Structs

The typical usage pattern for structs defined with Strukt more or less falls into one of the following buckets:

* Create a new struct, using the generated `new/1` function, which returns `{:ok, struct}` or `{:error, changeset}`
* Given a struct, and a set of changes, apply them to the struct using `change/2`, producing an `Ecto.Changeset`
* Given an `Ecto.Changeset` representing the struct, get back the struct using `from_changeset/1`,
which like `new/1`, returns `{:ok, struct}` or `{:error, changeset}`

Both `new/1` and `change/2` build on a common changeset function that performs casts for fields and embeds, and
runs all of the validation rules, including custom ones defined in `validate/1`. The primary difference between
the two is that `new/1` also performs autogeneration for fields (if applicable), and automatically invokes `from_changeset/1`
to get back the struct value.

If you need to do custom initialization of your own, then you can override `new/1` yourself, making sure that you
invoke `super(params)` at some point to perform all of the standard initialization logic. For example, if you wanted
to generate a primary key that is based on a hash of the contents of some fields of the struct, you might do something
like this:

    defmodule Thing do
      use Strukt

      defstruct do
        # This overrides the default primary key to disable autogeneration
        field :uuid, Ecto.UUID, primary_key: true
        field :name, :string
        field :email, string
      end

      def new(params \\ %{})

      def new(params) do
        with {:ok, thing} <- super(params) do
          hash =
            :crypto.hash_init(:sha256)
            |> :crypto.hash_update(thing.name)
            |> :crypto.hash_update(thing.email)
            |> :rypto.hash_final()
            |> Base.encode32()

          {:ok, %__MODULE__{thing | uuid: UUID.uuid5(:oid, hash, :default)}}
        end
      end
    end


### More Information

You may also find the [Schemas](guides/schemas.md) and [JSON](guides/json.md) documents useful for answering more specific questions about those features.
