defmodule Strukt.Field do
  @moduledoc false

  defstruct type: nil,
            name: nil,
            meta: nil,
            value_type: nil,
            options: [],
            validations: [],
            block: nil

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

  @supported_field_types [
    :field,
    :embeds_one,
    :embeds_many,
    :timestamps
  ]

  defguard is_supported(type) when type in @supported_field_types

  @doc """
  This function receives the AST of all field definitions provided to `defstruct`, and
  converts the nodes to a more useful form for the macro internals.

  The resulting struct can be converted back to an AST node with `to_ast/1`.

  This is intended for use only in the internal implementation of `defstruct`.
  """
  def parse(fields) do
    for {type, meta, args} <- fields, do: parse(type, meta, args)
  end

  defp parse(type, meta, [name, value_type]) when type in @supported_field_types,
    do: %__MODULE__{name: name, type: type, meta: meta, value_type: value_type}

  defp parse(type, meta, [name, value_type, opts]) when type in @supported_field_types do
    {block, opts} = Keyword.pop(opts, :do)
    {validations, options} = Keyword.split(opts, @validation_opts)

    %__MODULE__{
      name: name,
      type: type,
      meta: meta,
      value_type: value_type,
      block: block,
      options: options,
      validations: validations
    }
  end

  defp parse(type, meta, [name, value_type, opts, list]) when type in [:embeds_one, :embeds_many] do
    block = Keyword.fetch!(list, :do)
    {validations, options} = Keyword.split(opts, @validation_opts)

    %__MODULE__{
      name: name,
      type: type,
      meta: meta,
      value_type: value_type,
      block: block,
      options: options,
      validations: validations
    }
  end

  defp parse(:timestamps, meta, args),
    do: %__MODULE__{type: :timestamps, meta: meta, options: args}

  defp parse(field_type, _meta, args) do
    raise ArgumentError,
      message:
        "unsupported use of #{field_type}/#{length(args)} within `defstruct`, " <>
          "only #{Enum.join(@supported_field_types, ",")} are permitted"
  end

  @doc """
  This module converts a `Strukt.Field` struct into its AST form _without_ validations.
  """
  def to_ast(field)

  def to_ast(%__MODULE__{type: :timestamps, meta: meta, options: options}),
    do: {:timestamps, meta, options}

  def to_ast(%__MODULE__{
        type: type,
        name: name,
        meta: meta,
        value_type: value_type,
        options: options,
        block: nil
      }),
      do: {type, meta, [name, value_type, options]}

  def to_ast(%__MODULE__{
        type: type,
        name: name,
        meta: meta,
        value_type: value_type,
        options: options,
        block: block
      }),
      do: {type, meta, [name, value_type, options, block]}
end
