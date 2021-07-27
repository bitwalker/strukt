defmodule Strukt do
  @moduledoc """

  """
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
  you override `c:validate/1` instead. If you need to override this callback
  specifically for some reason, make sure you call `super/2` at some point during
  your implementation to ensure that validations are run.
  """
  @callback change(Ecto.Changeset.t() | term(), Keyword.t() | map()) :: Ecto.Changeset.t()

  @doc """
  This callback can be overridden to provide custom validation logic.

  The default implementation simply returns the changeset it is given. Validations
  defined inline with fields are handled by a specially generated `__validate__/1`
  function which is called directly by `new/1` and `change/2`.

  NOTE: If you override this function, there is no need to invoke `super/1`
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
      import Kernel, except: [defstruct: 1, defstruct: 2]
      import unquote(__MODULE__), only: :macros
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

    fields = Strukt.Field.parse(fields)

    define_struct(env, name, meta, moduledoc, derives, schema_attrs, fields, body)
  end

  # This clause handles the edge case where the definition only contains
  # a single field and nothing else
  defp define_struct(env, name, {type, _, _} = field) when is_supported(type) do
    fields = Strukt.Field.parse([field])

    define_struct(env, name, [], nil, [], [], fields, [])
  end

  defp define_struct(_env, name, meta, moduledoc, derives, schema_attrs, fields, body) do
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

          formed_params = transform_params(__MODULE__, params, struct)

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
              |> __validate__()
              |> validate()

            %__MODULE__{} = entity ->
              changeset(entity, params, :update)
          end
        end

        @doc """
        Validates a changeset for this type. Automatically called by `new/1`, `change/2`, and `changeset/{1,2}`.

        NOTE: This function can be overridden manually to provide additional validations above
        and beyond those defined by the schema itself, for cases where the validation options
        available are not rich enough to express the necessary business rules. By default this
        function just returns the input changeset, as `changeset` automatically applies the
        schema validations for you.
        """
        @impl Strukt
        def validate(cs), do: cs

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
    quote location: :keep, bind_quoted: [schema_module: env.module] do
      # Injects the type spec for this module based on the schema
      typespec_ast =
        Strukt.Typespec.generate(%Strukt.Typespec{
          caller: __MODULE__,
          info: @validated_fields,
          fields: @cast_fields,
          embeds: @cast_embed_fields
        })

      Module.eval_quoted(__ENV__, typespec_ast)

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
        |> __validate__()
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

      defp transform_params(module, nil = params, nil = struct), do: nil
      defp transform_params(_module, params, _struct)
           when is_map(params) and map_size(params) == 0,
           do: params

      defp transform_params(module, params, struct) when is_list(params) do
        for field <- module.__schema__(:fields), into: %{} do
          source_field_name = module.__schema__(:field_source, field)
          value = get_params_field_value(params, source_field_name, struct)
          map_value_to_field(module, field, value, struct)
        end
      end

      defp transform_params(module, params, struct) when is_map(params) do
        for field <- module.__schema__(:fields), into: %{} do
          source_field_name = module.__schema__(:field_source, field)
          value = get_params_field_value(params, source_field_name, struct)
          map_value_to_field(module, field, value, struct)
        end
      end

      defp transform_params(module, params, struct, cardinality: :one) do
        transform_params(module, params, struct)
      end

      defp transform_params(module, params, nil = struct, cardinality: :many) do
        Enum.with_index(params, fn param, index ->
          transform_params(module, param, struct)
        end)
      end

      defp transform_params(module, params, struct, cardinality: :many) do
        params
        |> Enum.with_index()
        |> Enum.map(fn {param, index} ->
          transform_params(module, param, Enum.at(struct, index))
        end)
      end

      defp map_value_to_field(module, field, value, struct) do
        case module.__schema__(:type, field) do
          {:parameterized, Ecto.Embedded,
           %Ecto.Embedded{
             cardinality: cardinality,
             related: embedded_module
           }} ->
            {field,
             transform_params(embedded_module, value, get_struct_field_value(struct, field),
               cardinality: cardinality
             )}

          _type ->
            {field, value}
        end
      end

      defp get_params_field_value(params, field, struct) when is_list(params) do
        case params[field] do
          nil -> get_struct_field_value(struct, field)
          value -> value
        end
      end

      defp get_params_field_value(params, field, struct) when is_map(params) do
        atom_key_value = Map.get(params, field)
        string_key_value = Map.get(params, field |> to_string())

        case {atom_key_value, string_key_value} do
          {nil, nil} -> get_struct_field_value(struct, field)
          {atom_key_value, nil} -> atom_key_value
          {nil, string_key_value} -> string_key_value
        end
      end

      defp get_struct_field_value(struct, field) do
        case struct do
          nil -> nil
          struct -> Map.get(struct, field)
        end
      end

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
        defimpl Jason.Encoder, for: schema_module do
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
