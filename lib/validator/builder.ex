defmodule Strukt.Validator.Builder do
  @moduledoc """
  This module compiles a validator pipeline.

  It is largely based on `Plug.Builder`, with minimal changes.
  """

  @doc """
  Compiles the pipeline.

  Each pipeline element should be a tuple of `{validator_name, options, guards}`

  This function expects a reversed pipeline, i.e. the last validator to be called
  comes first in the list.

  This function returns a tuple where the first element is a quoted reference to the
  changeset being validated, and the second element being the compiled quoted pipeline.


  ## Example

      Strukt.Validator.Builder.compile(env [
        {Strukt.Validators.RequireOnInsert, [:field], quote(do: changeset.action == :insert),
        {Strukt.Validators.RequireOnUpdate, [:other_field], quote(do: changeset.action == :update)},
        {Strukt.Validators.RequireOnChange, [:other_field], true},
      ], [])

  """
  def compile(env, pipeline, builder_opts \\ []) do
    module = env.module
    changeset = Macro.var(:changeset, __MODULE__)

    ast =
      Enum.reduce(pipeline, changeset, fn {validator, opts, guards}, acc ->
        {validator, opts, guards}
        |> init_validator()
        |> quote_validator(acc, env, builder_opts)
      end)

    {ast, _} =
      Macro.postwalk(ast, nil, fn
        # Ensure all guard references to the changeset binding in the resulting AST
        # refer to the correct context
        {:changeset, meta, context}, acc when context in [nil, module] ->
          {{:changeset, meta, __MODULE__}, acc}

        node, acc ->
          {node, acc}
      end)

    {changeset, ast}
  end

  defp init_validator({validator, opts, guards}) do
    case Atom.to_charlist(validator) do
      ~c"Elixir." ++ _ -> init_module_validator(validator, opts, guards)
      _ -> init_fun_validator(validator, opts, guards)
    end
  end

  defp init_module_validator(validator, opts, guards) do
    {:module, validator, quote(do: unquote(validator).init(unquote(escape(opts)))), guards}
  end

  defp init_fun_validator(validator, opts, guards) do
    {:function, validator, escape(opts), guards}
  end

  defp escape(opts), do: Macro.escape(opts, unquote: true)

  defp quote_validator({ty, validator, opts, guards}, acc, _env, _builder_opts) do
    call = quote_validator_call(ty, validator, opts)

    error_message =
      case ty do
        :module -> "expected #{inspect(validator)}.validate/2 to return an Ecto.Changeset"
        :function -> "expected #{validator}/2 to return an Ecto.Changeset"
      end <> ", all validators must receive a changeset and return a changeset"

    quote generated: true do
      case unquote(compile_guards(call, guards)) do
        %Ecto.Changeset{} = changeset ->
          unquote(acc)

        other ->
          raise unquote(error_message) <> ", got: #{inspect(other)}"
      end
    end
  end

  defp quote_validator_call(:function, validator, opts) do
    quote do: unquote(validator)(changeset, unquote(opts))
  end

  defp quote_validator_call(:module, validator, opts) do
    quote do: unquote(validator).validate(changeset, unquote(opts))
  end

  defp compile_guards(call, true), do: call

  defp compile_guards(call, guards) do
    quote do
      case true do
        true when unquote_splicing(guards) -> unquote(call)
        true -> changeset
      end
    end
  end
end
