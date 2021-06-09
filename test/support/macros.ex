defmodule Strukt.Test.Macros do
  defmacro __using__(_opts) do
    quote do
      use Strukt

      @timestamps_opts [type: :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}]
      @primary_key {:uuid, Ecto.UUID, autogenerate: true}
      @derives [Jason.Encoder]
    end
  end
end
