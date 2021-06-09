defmodule Strukt.Test.Fixtures do
  use Strukt

  defmodule Classic do
    @moduledoc "This module uses Kernel.defstruct/1, even though our defstruct/1 is in scope, since it is given only a list of field names"
    use Strukt

    defstruct [:name]
  end

  defmodule Simple do
    @moduledoc "This module represents the simplest possible use of defstruct/1"
    use Strukt

    defstruct do
      field(:name, :string, default: "")
    end
  end

  defstruct Inline do
    @moduledoc "This module represents the simplest possible use of defstruct/2, i.e. inline definition of a struct and its module"

    field(:name, :string, default: "")

    @doc "This function is defined in the Inline module"
    def test, do: true
  end

  defstruct Embedded do
    @moduledoc "This module demonstrates that embedding structs inline works just like the top-level"

    embeds_many :items, Item do
      field(:name, :string, required: [message: "must provide item name"])
    end
  end

  defstruct AltPrimaryKey do
    @moduledoc "This module demonstrates the use of a custom primary key, rather than the default of :uuid"

    field(:id, :integer, primary_key: true)
    field(:name, :string, default: "")
  end

  defstruct AttrPrimaryKey do
    @moduledoc "This module demonstrates the use of a custom primary key, using the @primary_key attribute"

    @primary_key {:id, :integer, autogenerate: {System, :unique_integer, []}}

    field(:name, :string, default: "")
  end

  defstruct JSON do
    @moduledoc "This module demonstrates how to derive JSON serialization for your struct"

    @timestamps_opts [type: :utc_datetime_usec]
    @derives [Jason.Encoder]

    field(:name, :string, default: "")

    timestamps(autogenerate: {DateTime, :utc_now, []})
  end

  defmodule OuterAttrs do
    use Strukt

    @derives [Jason.Encoder]
    @timestamps_opts [type: :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}]

    defstruct do
      field(:name, :string, default: "")

      timestamps()
    end
  end

  defmodule OuterScope do
    # This imports defstruct and sets up shared defaults in the outer scope
    use Strukt.Test.Macros

    defstruct InnerScope do
      # Since this is a new module scope, we want to set up defaults
      # like we did in the outer scope.  If working properly,
      # this macro should be expanded before the schema definition
      use Strukt.Test.Macros

      field(:name, :string, default: "")

      timestamps()
    end
  end

  defstruct Validations do
    @moduledoc "This module uses a variety of validation rules in various combinations"

    field(:name, :string, default: "", required: true)
    field(:email, :string, required: [message: "must provide an email"], format: ~r/^.+@.+$/)
    field(:age, :integer, number: [greater_than: 0])
    field(:status, Ecto.Enum, values: [:red, :green, :blue])

    @doc "This is an override of the validate/1 callback, where you can add additional validations to be run automatically"
    def validate(changeset) do
      changeset
      |> validate_length(:name, min: 2, max: 100)
    end
  end

  defstruct ValidateRequiredEmbed do
    embeds_one :embedded, Embed, [required: [message: "embed must be set"]] do
      field(:name, :string, required: true)
    end
  end

  defstruct ValidateLengths do
    @moduledoc "This module excersizes validations on string length"

    field(:exact, :string,
      required: [message: "must be 3 characters"],
      length: [is: 3, message: "must be 3 characters"]
    )

    field(:bounded_graphemes, :string,
      required: [message: "must be between 1 and 3 graphemes"],
      length: [min: 1, max: 3, message: "must be between 1 and 3 graphemes"]
    )

    field(:bounded_bytes, :string,
      required: [message: "must be between 1 and 3 bytes"],
      length: [count: :bytes, min: 1, max: 3, message: "must be between 1 and 3 bytes"]
    )
  end

  defstruct ValidateSets do
    @moduledoc "This module excersizes validations based on set membership"

    field(:one_of, :string, one_of: [values: ["a", "b", "c"], message: "must be one of [a, b, c]"])

    field(:none_of, :string,
      none_of: [values: ["a", "b", "c"], message: "cannot be one of [a, b, c]"]
    )

    field(:subset_of, {:array, :string}, subset_of: [values: ["a", "b", "c"]])
  end

  defstruct ValidateNumbers do
    @moduledoc "This module excersizes validations on numbers"

    field(:bounds, :integer, number: [greater_than: 1, less_than: 100])

    field(:bounds_inclusive, :integer,
      number: [greater_than_or_equal_to: 1, less_than_or_equal_to: 100]
    )

    field(:eq, :integer, number: [equal_to: 1])
    field(:neq, :integer, number: [not_equal_to: 1])
    field(:range, :integer, range: 1..100)
  end
end
