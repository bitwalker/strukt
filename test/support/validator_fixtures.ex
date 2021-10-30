defmodule Strukt.Test.Validators do
  defmodule ValidateFileAndContentType do
    use Strukt.Validator

    @impl true
    def init(allowed_content_types) when is_list(allowed_content_types),
      do: allowed_content_types

    @impl true
    def validate(changeset, allowed) do
      case Ecto.Changeset.fetch_field(changeset, :filename) do
        {:changes, filename} ->
          case Ecto.Changeset.fetch_field(changeset, :content_type) do
            {:changes, content_type} ->
              cond do
                not Enum.member?(allowed, content_type) ->
                  Ecto.Changeset.add_error(
                    changeset,
                    :content_type,
                    "content type is not allowed"
                  )

                matching_type?(filename, content_type) ->
                  changeset

                :else ->
                  Ecto.Changeset.add_error(
                    changeset,
                    :content_type,
                    "mismatched content type and file extension"
                  )
              end

            {:data, content_type} ->
              if matching_type?(filename, content_type) do
                changeset
              else
                Ecto.Changeset.add_error(
                  changeset,
                  :filename,
                  "filename must match content type of file"
                )
              end

            :error ->
              Ecto.Changeset.put_change(
                changeset,
                :content_type,
                filename_to_content_type(filename)
              )
          end

        {:data, filename} ->
          case Ecto.Changeset.fetch_field(changeset, :content_type) do
            {:changes, content_type} ->
              cond do
                not Enum.member?(allowed, content_type) ->
                  Ecto.Changeset.add_error(
                    changeset,
                    :content_type,
                    "content type is not allowed"
                  )

                matching_type?(filename, content_type) ->
                  changeset

                :else ->
                  Ecto.Changeset.add_error(
                    changeset,
                    :content_type,
                    "mismatched content type and file extension"
                  )
              end

            {:data, _} ->
              changeset

            :error ->
              Ecto.Changeset.put_change(
                changeset,
                :content_type,
                filename_to_content_type(filename)
              )
          end

        :error ->
          Ecto.Changeset.add_error(changeset, :filename, "expected filename")
      end
    end

    defp filename_to_content_type(filename) do
      # This is obviously not comprehensive
      case :filename.extension(filename) do
        "." <> ext when ext in ["csv", "tsv", "plain", "html"] -> "text/#{ext}"
        "." <> ext -> "application/#{ext}"
        ext when ext in [".", ""] -> "application/octet-stream"
      end
    end

    defp matching_type?(filename, content_type),
      do: filename_to_content_type(filename) == content_type
  end
end
