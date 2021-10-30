defmodule Strukt.Validator do
  @moduledoc """
  This module defines the behaviour for validator modules which
  can be used in validation pipelines over Strukt-defined structs.
  """
  @type opts :: any()

  @doc """
  This is called during validation to generate the options provided
  to `validate/2`. The input is whatever was given as the second argument
  to `Strukt.validation/2`, and any term is allowed to be returned. The
  return value will be passed as-is to the `validate/2` callback.
  """
  @callback init(opts()) :: opts()

  @doc """
  Called during validation.

  The implementation is allowed to mutate the changeset as desired,
  but must return a new changeset regardless of whether the changeset
  it received was valid or not, but with relevant errors added.
  """
  @callback validate(Ecto.Changeset.t(), opts()) :: Ecto.Changeset.t()

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      import Ecto.Changeset

      @impl unquote(__MODULE__)
      def init(opts), do: opts

      defoverridable init: 1
    end
  end
end
