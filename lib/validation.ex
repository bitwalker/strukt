defmodule Strukt.Validation do
  @moduledoc false

  @validation_opts [
    :required,
    :length,
    :format,
    :one_of,
    :none_of,
    :subset_of,
    :range,
    :number
  ]

  @doc """
  Given the calling module in which a struct is being defined, and validation metadata
  about the fields of that struct; this function generates AST for an optimized validation
  function that applies all of the known validation rules to an `Ecto.Changeset` for an
  instance of the struct.

  For example, given the following struct definition:

      defstruct Settings do
        field :name, :string, required: true
        field :volume, :integer, required: [message: "must set volume"], range: 0..100
        field :custom, :map, default: %{}
      end

  The following function would be defined:

      def __validate__(changeset) do
        changeset
        |> Ecto.Changeset.validate_required(:name, [])
        |> Ecto.Changeset.validate_required(:volume, message: "must set volume")
        |> Ecto.Changeset.validate_inclusion(:volume, 0..100, message: "must be in the range 0..100")
      end

  """
  def generate(caller, fields) do
    validations =
      fields
      |> Enum.flat_map(fn {name, info} ->
        {validations, _info} = Map.split(info, @validation_opts)
        Enum.map(validations, fn {v, data_or_opts} -> {name, v, data_or_opts} end)
      end)

    has_validations? = length(validations) > 0

    if has_validations? do
      quote location: :keep, generated: true, context: caller do
        defp __validate__(changeset) do
          unquote(generate_body(caller, validations))
        end
      end
    else
      quote context: caller do
        defp __validate__(changeset), do: changeset
      end
    end
  end

  defp generate_body(caller, validations) do
    validations
    |> Enum.reduce(Macro.var(:changeset, caller), fn {field, validation, data_or_opts}, acc ->
      ast =
        case validation do
          :required when is_boolean(data_or_opts) ->
            quote do
              Ecto.Changeset.validate_required(unquote(field), trim: true)
            end

          :required when is_list(data_or_opts) ->
            opts = Keyword.merge([trim: true], data_or_opts)

            quote do
              Ecto.Changeset.validate_required(unquote(field), unquote(Macro.escape(opts)))
            end

          :format ->
            cond do
              is_struct(data_or_opts, Regex) ->
                quote do
                  Ecto.Changeset.validate_format(
                    unquote(field),
                    unquote(Macro.escape(data_or_opts))
                  )
                end

              Keyword.keyword?(data_or_opts) ->
                pattern = Keyword.fetch!(data_or_opts, :pattern)
                opts = Keyword.drop(data_or_opts, [:pattern])

                quote do
                  Ecto.Changeset.validate_format(
                    unquote(field),
                    unquote(Macro.escape(pattern)),
                    unquote(Macro.escape(opts))
                  )
                end

              :else ->
                raise ArgumentError,
                  message:
                    "invalid :format specifier for field #{inspect(field)}, " <>
                      "expected regex, or keyword list with :pattern that is regex, got: #{inspect(data_or_opts)}"
            end

          :length when is_list(data_or_opts) ->
            quote do
              Ecto.Changeset.validate_length(
                unquote(field),
                unquote(Macro.escape(data_or_opts))
              )
            end

          :range ->
            cond do
              match?(%Range{}, data_or_opts) ->
                range = Macro.escape(data_or_opts)

                quote do
                  Ecto.Changeset.validate_inclusion(
                    unquote(field),
                    unquote(range),
                    message: "must be in the range #{inspect(unquote(range))}"
                  )
                end

              Keyword.keyword?(data_or_opts) ->
                range = Macro.escape(Keyword.fetch!(data_or_opts, :value))
                opts = Macro.escape(Keyword.drop(data_or_opts, [:value]))

                quote do
                  Ecto.Changeset.validate_inclusion(
                    unquote(field),
                    unquote(range),
                    Keyword.merge(
                      [message: "must be in the range #{inspect(range)}"],
                      unquote(opts)
                    )
                  )
                end

              :else ->
                raise ArgumentError,
                  message:
                    "invalid :range specifier for field #{inspect(field)}, " <>
                      "expected a Range, got: #{inspect(data_or_opts)}"
            end

          :number when is_list(data_or_opts) ->
            quote do
              Ecto.Changeset.validate_number(
                unquote(field),
                unquote(Macro.escape(data_or_opts))
              )
            end

          :one_of when is_list(data_or_opts) ->
            if Keyword.keyword?(data_or_opts) do
              data = Keyword.fetch!(data_or_opts, :values)
              opts = Keyword.drop(data_or_opts, [:values])

              quote do
                Ecto.Changeset.validate_inclusion(
                  unquote(field),
                  unquote(Macro.escape(data)),
                  unquote(Macro.escape(opts))
                )
              end
            else
              quote do
                Ecto.Changeset.validate_inclusion(
                  unquote(field),
                  unquote(Macro.escape(data_or_opts))
                )
              end
            end

          :one_of ->
            quote do
              Ecto.Changeset.validate_inclusion(
                unquote(field),
                unquote(Macro.escape(data_or_opts))
              )
            end

          :none_of when is_list(data_or_opts) ->
            if Keyword.keyword?(data_or_opts) do
              data = Keyword.fetch!(data_or_opts, :values)
              opts = Keyword.drop(data_or_opts, [:values])

              quote do
                Ecto.Changeset.validate_exclusion(
                  unquote(field),
                  unquote(Macro.escape(data)),
                  unquote(Macro.escape(opts))
                )
              end
            else
              quote do
                Ecto.Changeset.validate_exclusion(
                  unquote(field),
                  unquote(Macro.escape(data_or_opts))
                )
              end
            end

          :none_of ->
            quote do
              Ecto.Changeset.validate_exclusion(
                unquote(field),
                unquote(Macro.escape(data_or_opts))
              )
            end

          :subset_of when is_list(data_or_opts) ->
            if Keyword.keyword?(data_or_opts) do
              data = Keyword.fetch!(data_or_opts, :values)
              opts = Keyword.drop(data_or_opts, [:values])

              quote do
                Ecto.Changeset.validate_subset(
                  unquote(field),
                  unquote(Macro.escape(data)),
                  unquote(Macro.escape(opts))
                )
              end
            else
              quote do
                Ecto.Changeset.validate_subset(
                  unquote(field),
                  unquote(Macro.escape(data_or_opts))
                )
              end
            end

          :subset_of ->
            quote do
              Ecto.Changeset.validate_subset(
                unquote(field),
                unquote(Macro.escape(data_or_opts))
              )
            end

          _ ->
            raise ArgumentError,
              message:
                "invalid #{inspect(validation)} specifier for field #{field} with data/options: #{inspect(data_or_opts)}"
        end

      Macro.pipe(acc, ast, 0)
    end)
  end
end
