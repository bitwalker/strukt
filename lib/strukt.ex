defmodule Strukt do
  import Kernel, except: [defstruct: 1, defstruct: 2]
  import Strukt.Field, only: [is_supported: 1]

  @doc """
  See `c:new/1`
  """
  @callback new() :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  @doc """
  This callback can be overridden to provide custom initialization behavior.

  The default implementation provided for you performs all of the necessary
  validation and autogeneration of fields with those options set.

  NOTE: It is critical that if you do override this callback, that you call
  `super/1` to run the default implementation at some point in your implementation.
  """
  @callback new(Keyword.t() | map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}

  @doc """
  See `c:change/2`
  """
  @callback change(Ecto.Changeset.t() | term()) :: Ecto.Changeset.t()

  @doc """
  This callback can be overridden to provide custom change behavior.

  The default implementation provided for you creates a changeset and applies
  all of the inline validations defined on the schema.

  NOTE: It is recommended that if you need to perform custom validations, that
  you use the `validation/1` and `validation/2` facility for performing custom
  validations in a module or function, and if necessary, override `c:validate/1`
  instead of performing validations in this callback. If you need to override this
  callback specifically for some reason, make sure you call `super/2` at some point during
  your implementation to ensure that validations are run.
  """
  @callback change(Ecto.Changeset.t() | term(), Keyword.t() | map()) :: Ecto.Changeset.t()

  @doc """
  This callback can be overridden to manually implement your own validation logic.

  The default implementation handles invoking the validation rules expressed inline
  or via the `validation/1` and `validation/2` macros. You may still invoke the default
  validations from your own implementation using `super/1`.

  This function can be called directly on a changeset, and is automatically invoked
  by the default `new/1` and `change/2` implementations.
  """
  @callback validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()

  @field_types [
    :field,
    :embeds_one,
    :embeds_many,
    :belongs_to,
    :has_many,
    :has_one,
    :many_to_many,
    :timestamps
  ]

  @schema_attrs [
    :primary_key,
    :schema_prefix,
    :foreign_key_type,
    :timestamps_opts,
    :derive,
    :field_source_mapper
  ]

  @special_attrs @schema_attrs ++ [:moduledoc, :derives]

  defmacro __using__(_) do
    quote do
      import Kernel, except: [defstruct: 1, defstruct: 2, validation: 1, validation: 2]
      import unquote(__MODULE__), only: :macros
    end
  end

  @doc """
  Defines a validation rule for the current struct validation pipeline.

  A validation pipeline is constructed by expressing the rules in the order
  in which you want them applied, from top down. The validations may be defined
  anywhere in the module, but the order of application is always top down.

  You may define either module validators or function validators, much like `Plug.Builder`.
  For module validators, the module is expected to implement the `Strukt.Validator` behavior,
  consisting of the `init/1` and `validate/2` callbacks. For function validators, they are
  expected to be of arity 2. Both the `validate/2` callback and function validators receive
  the changeset to validate/manipulate as their first argument, and options passed to the
  `validation/2` macro, if provided.

  ## Guards

  Validation rules that should be applied conditionally can either handle the conditional
  logic in their implementation, or if simple, can use guards to express this instead, which
  can be more efficient.

  Guards may use the changeset being validated in their conditions by referring to `changeset`.
  See the example below to see how these can be expressed.

  ## Example

      defmodule Upload do
        use Strukt

        @allowed_content_types ["application/json", "application/pdf", "text/csv"]

        defstruct do
          field :filename, :string
          field :content, :binary, default: <<>>
          field :content_type, :string, required: true
        end

        # A simple function validator, expects a function in the same module
        validation :validate_filename

        # A function validator with a guard clause, only applied when the guard is successful
        validation :validate_content_type when is_map_key(changeset.changes, :content_type)

        # A module validator with options
        validation MyValidations.EnsureContentMatchesType, @allowed_content_types

        # A validator with options and a guard clause
        validation :example, [foo: :bar] when changeset.action == :update

        defp validate_filename(changeset, _opts), do: changeset
      end
  """
  defmacro validation(validator, opts \\ [])

  defmacro validation({:when, _meta, [validator | guards]}, opts) do
    validator = Macro.expand(validator, %{__CALLER__ | function: {:init, 1}})

    quote do
      @strukt_validators {unquote(validator), unquote(opts),
                          unquote(Macro.escape(guards, unquote: true))}
    end
  end

  defmacro validation(validator, opts) do
    validator = Macro.expand(validator, %{__CALLER__ | function: {:init, 1}})

    quote do
      @strukt_validators {unquote(validator), unquote(opts), true}
    end
  end

  @doc ~S"""
  This variant of `defstruct` can accept a list of fields, just like `Kernel.defstruct/1`, in which
  case it simply defers to `Kernel.defstruct/1` and does nothing; or it can be passed a block
  containing an `Ecto.Schema` definition. The resulting struct/schema is defined in the current
  module scope, and will inherit attributes like `@derive`, `@primary_key`, etc., which are already
  defined in the current scope.

  ## Example

      defmodule Passthrough do
        use Strukt

        defstruct [:name]
      end

      defmodule Person do
        use Strukt

        @derive [Jason.Encoder]
        defstruct do
          field :name, :string
        end

        def say_hello(%__MODULE__{name: name}), do: "Hello #{name}!"
      end

  Above, even though `Strukt.defstruct/1` is in scope, it simply passes through the list of fields
  to `Kernel.defstruct/1`, as without a proper schema, there isn't much useful we can do. This allows
  intermixing uses of `defstruct/1` in the same scope without conflict.
  """
  defmacro defstruct(arg)

  defmacro defstruct(do: block) do
    define_struct(__CALLER__, nil, block)
  end

  defmacro defstruct(fields) do
    quote bind_quoted: [fields: fields] do
      Kernel.defstruct(fields)
    end
  end

  @doc ~S"""
  This variant of `defstruct` takes a module name and block containing a struct schema and
  any other module contents desired, and defines a new module with that name, generating
  a struct just like `Strukt.defstruct/1`.

  ## Example

      use Strukt

      defstruct Person do
        @derive [Jason.Encoder]

        field :name, :string

        def say_hello(%__MODULE__{name: name}), do: "Hello #{name}!"
      end

  NOTE: Unlike `Strukt.defstruct/1`, which inherits attributes like `@derive` or `@primary_key` from
  the surrounding scope; this macro requires them to be defined in the body, as shown above.
  """
  defmacro defstruct(name, do: body) do
    define_struct(__CALLER__, name, body)
  end

  defp define_struct(env, name, {:__block__, meta, body}) do
    {special_attrs, body} =
      Enum.split_with(body, fn
        {:@, _, [{attr, _, _}]} -> attr in @special_attrs
        _ -> false
      end)

    {fields, body} =
      Enum.split_with(body, fn
        {field_type, _, _} -> field_type in @field_types
        _ -> false
      end)

    {schema_attrs, special_attrs} =
      Enum.split_with(special_attrs, fn {:@, _, [{attr, _, _}]} -> attr in @schema_attrs end)

    moduledoc = Enum.find(special_attrs, fn {:@, _, [{attr, _, _}]} -> attr == :moduledoc end)

    derives =
      case Enum.find(special_attrs, fn {:@, _, [{attr, _, _}]} -> attr == :derives end) do
        {_, _, [{_, _, [derives]}]} ->
          derives

        nil ->
          []
      end

    opaque_fields = Enum.any?(special_attrs, fn {:@, _, [{attr, _, [value]}]} -> attr == :opaque_fields &&!!value end)

    fields = Strukt.Field.parse(fields)

    define_struct(env, name, meta, moduledoc, derives, opaque_fields, schema_attrs, fields, body)
  end

  # This clause handles the edge case where the definition only contains
  # a single field and nothing else
  defp define_struct(env, name, {type, _, _} = field) when is_supported(type) do
    fields = Strukt.Field.parse([field])

    define_struct(env, name, [], nil, [], false, [], fields, [])
  end

  defp define_struct(_env, name, meta, moduledoc, derives, opaque_fields, schema_attrs, fields, body) do
    # Extract macros which should be defined at the top of the module
    {macros, body} =
      Enum.split_with(body, fn
        {node, _meta, _body} -> node in [:use, :import, :alias]
        _ -> false
      end)

    # Extract child struct definitions
    children =
      fields
      |> Enum.filter(fn %{type: t, block: block} ->
        t in [:embeds_one, :embeds_many] and block != nil
      end)
      |> Enum.map(fn %{value_type: value_type, block: block} ->
        quote do
          Strukt.defstruct unquote(value_type) do
            unquote(block)
          end
        end
      end)

    # Generate validation metadata for the generated module
    validated_fields =
      for %{name: name, type: t} = f <- fields, t != :timestamps, reduce: {:%{}, [], []} do
        {node, meta, elements} ->
          kvs =
            Keyword.merge(
              [type: t, value_type: f.value_type, default: f.options[:default]],
              f.validations
            )

          element = {name, {:%{}, [], kvs}}
          {node, meta, [element | elements]}
      end

    # Get a list of fields valid for `cast/3`
    cast_fields = for %{type: :field} = f <- fields, do: f.name

    # Get a list of embeds valid for `cast_embed/3`
    cast_embed_fields = for %{type: t} = f <- fields, t in [:embeds_one, :embeds_many], do: f.name

    # Expand fields back to their final AST form
    fields_ast =
      fields
      |> Stream.map(&Strukt.Field.to_ast/1)
      # Drop any extraneous args (such as inline schema definitions, which have been extracted)
      |> Enum.map(fn {type, meta, args} -> {type, meta, Enum.take(args, 3)} end)

    # Make sure the default primary key is defined and castable
    defines_primary_key? =
      Enum.any?(fields, &(&1.type == :field and Keyword.has_key?(&1.options, :primary_key)))

    quoted =
      quote location: :keep do
        unquote(moduledoc)
        unquote_splicing(macros)

        # Capture schema attributes from outer scope, since `use Ecto.Schema` will reset them
        schema_attrs =
          unquote(@schema_attrs)
          |> Enum.map(&{&1, Module.get_attribute(__MODULE__, &1)})
          |> Enum.reject(fn {_, value} -> is_nil(value) end)

        use Ecto.Schema
        import Ecto.Changeset, except: [change: 2]

        @behaviour unquote(__MODULE__)
        @before_compile unquote(__MODULE__)

        Module.register_attribute(__MODULE__, :strukt_validators, accumulate: true)

        # Generate child structs before generating the parent
        unquote_splicing(children)

        # Ensure any schema attributes are set, starting with outer scope, then inner
        for {schema_attr, value} <- schema_attrs do
          Module.put_attribute(__MODULE__, schema_attr, value)
        end

        # Schema attributes defined in module body
        unquote_splicing(schema_attrs)

        # Ensure a primary key is defined, if one hasn't been by this point
        defines_primary_key? = unquote(defines_primary_key?)

        case Module.get_attribute(__MODULE__, :primary_key) do
          nil when not defines_primary_key? ->
            # Provide the default primary key
            Module.put_attribute(__MODULE__, :primary_key, {:uuid, Ecto.UUID, autogenerate: true})

          pk when defines_primary_key? ->
            # Primary key is being overridden
            Module.put_attribute(__MODULE__, :primary_key, false)

          _pk ->
            # Primary key is set and not overridden
            nil
        end

        @schema_name Macro.underscore(__MODULE__)
        @opaque_fields unquote(opaque_fields)
        @validated_fields unquote(validated_fields)
        @cast_embed_fields unquote(Macro.escape(cast_embed_fields))

        # Ensure primary key can be cast, if applicable
        case Module.get_attribute(__MODULE__, :primary_key) do
          false ->
            # Primary key was explicitly disabled
            Module.put_attribute(__MODULE__, :cast_fields, unquote(Macro.escape(cast_fields)))

          {pk, _type, _opts} ->
            # Primary key was defaulted, or set manually via attribute
            Module.put_attribute(__MODULE__, :cast_fields, [
              pk | unquote(Macro.escape(cast_fields))
            ])
        end

        # Inject or override @derives, without Jason.Encoder if present
        case Module.get_attribute(__MODULE__, :derives) do
          derives when derives in [false, nil] or derives == [] ->
            case unquote(derives) do
              nil ->
                nil

              ds ->
                if Enum.member?(ds, Jason.Encoder) do
                  Module.put_attribute(__MODULE__, :derives_jason, true)

                  Module.put_attribute(
                    __MODULE__,
                    :derives,
                    Enum.reject(ds, &(&1 == Jason.Encoder))
                  )
                end
            end

          derives ->
            if Enum.member?(derives, Jason.Encoder) do
              Module.put_attribute(__MODULE__, :derives_jason, true)

              Module.put_attribute(
                __MODULE__,
                :derives,
                Enum.reject(derives, &(&1 == Jason.Encoder))
              )
            end
        end

        embedded_schema do
          unquote({:__block__, meta, fields_ast})
        end

        @doc """
        Creates a `#{__MODULE__}`, using the provided params.

        This operation is fallible, so it returns `{:ok, t}` or `{:error, Ecto.Changeset.t}`.

        If this struct has an autogenerated primary key, it will be generated, assuming it
        was not provided in the set of params. By default, all structs generated by `defstruct`
        are given a primary key field of `:uuid`, which is autogenerated using `UUID.uuid/4`.
        See the docs for `defstruct` if you wish to change this.
        """
        @impl Strukt
        def new(params \\ %{})

        def new(params) do
          struct =
            struct(__MODULE__)
            |> Strukt.Autogenerate.generate()

          formed_params = Strukt.Params.transform(__MODULE__, params, struct)

          struct
          |> changeset(formed_params, :insert)
          |> from_changeset()
        end

        @doc """
        Prepares an `Ecto.Changeset` from a struct, or an existing `Ecto.Changeset`, by applying
        the provided params as changes. The resulting changeset is validated.

        See `from_changeset/1`, for converting the changeset back to a struct.
        """
        @impl Strukt
        def change(entity_or_changeset, params \\ %{})

        def change(entity_or_changeset, params) do
          case entity_or_changeset do
            %Ecto.Changeset{} = cs ->
              cs
              |> Ecto.Changeset.change(params)
              |> validate()

            %__MODULE__{} = entity ->
              changeset(entity, params, :update)
          end
        end

        @doc """
        Validates a changeset for this type.
        """
        @impl Strukt
        def validate(changeset) do
          changeset
          |> __validate__()
          |> validator_builder_call([])
        end

        defoverridable unquote(__MODULE__)

        unquote(body)
      end

    if is_nil(name) do
      quoted
    else
      quote do
        defmodule unquote(name) do
          unquote(quoted)
        end
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    schema_module = env.module
    validators = Module.get_attribute(env.module, :strukt_validators)

    {changeset, validate_body} = Strukt.Validator.Builder.compile(env, validators, [])

    quote location: :keep do
      # Injects the type spec for this module based on the schema
      typespec_ast =
        Strukt.Typespec.generate(%Strukt.Typespec{
          caller: __MODULE__,
          opaque: @opaque_fields,
          info: @validated_fields,
          fields: @cast_fields,
          embeds: @cast_embed_fields
        })

      Module.eval_quoted(__ENV__, typespec_ast)

      defp validator_builder_call(unquote(changeset), opts),
        do: unquote(validate_body)

      @doc """
      Generates an `Ecto.Changeset` for this type, using the provided params.

      This function automatically performs validations based on the schema, and additionally,
      it invokes `validate/1` in order to apply custom validations, if present.

      Use `from_changeset/1` to apply the changes in the changeset,
      and get back a valid instance of this type
      """
      @spec changeset(t) :: Ecto.Changeset.t()
      @spec changeset(t, Keyword.t() | map()) :: Ecto.Changeset.t()
      def changeset(%__MODULE__{} = entity, params \\ %{}) do
        changeset(entity, params, nil)
      end

      # This function is used to build and validate a changeset for the corresponding action.
      @doc false
      def changeset(%__MODULE__{} = entity, params, action)
          when action in [:insert, :update, :delete, nil] do
        params =
          case params do
            %__MODULE__{} ->
              Map.from_struct(params)

            m when is_map(m) ->
              m

            other ->
              Enum.into(other, %{})
          end

        cast(entity, params, @cast_fields)
        |> Map.put(:action, action)
        |> __cast_embeds__(@cast_embed_fields)
        |> validate()
      end

      defp __cast_embeds__(changeset, []), do: changeset

      if length(@cast_embed_fields) > 0 do
        defp __cast_embeds__(%Ecto.Changeset{params: params} = changeset, [field | fields]) do
          # If we get a struct(s) in the params for an embed, there is no need to cast, presume validity and apply the change directly
          f = to_string(field)
          prev = Ecto.Changeset.fetch_field!(changeset, field)

          # Ensure a change can always be applied, whether inserting or updated
          changeset =
            case Map.get(params, f) do
              nil ->
                changeset

              %_{} = entity when is_nil(prev) ->
                # In this case, we don't have a previous instance, and we don't need to cast
                Ecto.Changeset.put_embed(changeset, field, Map.from_struct(entity))

              %_{} = entity ->
                # In this case, we have a previous instance, so we need to change appropriately, but we don't need to cast
                cs = Ecto.Changeset.change(prev, Map.from_struct(entity))
                Ecto.Changeset.put_embed(changeset, field, cs)

              [%_{} | _] = entities ->
                # When we have a list of entities, we are overwriting the embeds with a new set
                Ecto.Changeset.put_embed(changeset, field, Enum.map(entities, &Map.from_struct/1))

              other when is_map(other) or is_list(other) ->
                # For all other parameters, we need to cast. Depending on how the embedded entity is configured, this may raise an error
                cast_embed(changeset, field)
            end

          __cast_embeds__(changeset, fields)
        end
      end

      @doc """
      Applies the changes in the changset if the changeset is valid, returning the
      updated data. The action must be one of `:insert`, `:update`, or `:delete` and
      is used

      Returns `{:ok, t}` or `{:error, Ecto.Changeset.t}`, depending on validity of the changeset
      """
      @spec from_changeset(Ecto.Changeset.t()) :: {:ok, t} | {:error, Ecto.Changeset.t()}
      def from_changeset(changeset)

      def from_changeset(%Ecto.Changeset{valid?: true} = cs),
        do: {:ok, Ecto.Changeset.apply_changes(cs)}

      def from_changeset(%Ecto.Changeset{} = cs), do: {:error, cs}

      @doc "Deserialize this type from a JSON string or iodata"
      @spec from_json(binary | iodata) :: {:ok, t} | {:error, reason :: term}
      def from_json(input) do
        with {:ok, map} <- Jason.decode(input, keys: :atoms!, strings: :copy) do
          {:ok, Ecto.embedded_load(__MODULE__, map, :json)}
        end
      end

      # Generate the __validate__ function
      validate_ast = Strukt.Validation.generate(__MODULE__, @validated_fields)
      Module.eval_quoted(__ENV__, validate_ast)

      # Handle conditional implementation of Jason.Encoder
      if Module.get_attribute(__MODULE__, :derives_jason) do
        defimpl Jason.Encoder, for: unquote(schema_module) do
          def encode(value, opts) do
            value
            |> Ecto.embedded_dump(:json)
            |> Jason.Encode.map(opts)
          end
        end
      end
    end
  end
end
