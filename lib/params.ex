defmodule Strukt.Params do
  @moduledoc """
    use Ecto.Schema's reflection to map the params.
  """

  def transform(_module, nil = _params, nil = _struct), do: nil
  # def transform(_module = nil, )

  def transform(_module, params, _struct)
      when is_map(params) and map_size(params) == 0,
      do: params

  def transform(module, %{__struct__: _} = params, nil = _struct) do
    transform_from_struct(module, params, params)
  end

  def transform(module, params, nil = _struct) do
    struct =
      struct(module)
      |> Strukt.Autogenerate.generate()

    transform_from_struct(module, params, struct)
  end

  def transform(module, params, %{__struct__: _} = struct) do
    transform_from_struct(module, params, struct)
  end

  defp transform(module, params, struct, cardinality: :one) do
    transform(module, params, struct)
  end

  defp transform(module, params, nil = struct, cardinality: :many) when is_list(params) do
    Enum.map(params, fn param ->
      transform(module, param, struct)
    end)
  end

  defp transform(module, params, struct, cardinality: :many) when is_list(params) do
    params
    |> Enum.with_index()
    |> Enum.map(fn {param, index} ->
      transform(module, param, Enum.at(struct, index))
    end)
  end

  # for delay the type error to casting
  defp transform(_module, params, _struct, cardinality: :many), do: params

  defp transform_from_struct(module, params, struct) do
    struct
    |> Map.from_struct()
    |> Map.to_list()
    |> Enum.map(fn {key, _value} ->
      case module.__schema__(:field_source, key) do
        nil ->
          {key, get_params_field_value(params, key, struct)}

        source_field_name ->
          value = get_params_field_value(params, source_field_name, struct)
          map_value_to_field(module, key, value, struct)
      end
    end)
    |> Map.new()
  end

  defp map_value_to_field(module, field, value, struct) do
    case module.__schema__(:type, field) do
      {:parameterized, Ecto.Embedded,
       %Ecto.Embedded{
         cardinality: cardinality,
         related: embedded_module
       }} ->
        {field,
         transform(embedded_module, value, get_struct_field_value(struct, field),
           cardinality: cardinality
         )}

      _type ->
        {field, value}
    end
  end

  defp get_params_field_value(nil, _field, _struct), do: nil

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
end
