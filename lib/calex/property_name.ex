defmodule Calex.PropertyName do
  @moduledoc """
  Validates iCalendar property names according to RFC 5545.
  """

  alias Calex.DecodeError

  @type validation_error ::
          :empty
          | :invalid_characters
          | :invalid_x_name

  @doc """
  Parses a property name according to RFC 5545.
  """
  @spec parse(String.t()) :: {:ok, String.t()} | {:error, validation_error()}
  def parse(name) when is_binary(name) do
    name = String.trim(name)

    cond do
      name == "" ->
        {:error, :empty}

      x_name?(name) or iana_token?(name) ->
        {:ok, name}

      String.starts_with?(name, "X-") or String.starts_with?(name, "x-") ->
        {:error, :invalid_x_name}

      true ->
        {:error, :invalid_characters}
    end
  end

  @doc """
  Parses a property name according to RFC 5545 and raises an error if it is invalid.
  """
  @spec parse!(String.t()) :: String.t() | no_return()
  def parse!(name) when is_binary(name) do
    case parse(name) do
      {:ok, name} ->
        name

      {:error, error} ->
        raise DecodeError, message: "property key invalid: #{inspect(name)} (reason: #{error})"
    end
  end

  # Matches X- names: "X-" followed by one or more ALPHA/DIGIT/HYPHEN
  defp x_name?(<<h1, h2, rest::binary>>) when h1 in ?X..?X or h1 in ?x..?x do
    h2 == ?- and valid_token?(rest)
  end

  defp x_name?(_), do: false

  # Matches IANA token: one or more ALPHA/DIGIT/HYPHEN
  defp iana_token?(name), do: valid_token?(name)

  defp valid_token?(name) do
    name != "" and
      String.to_charlist(name)
      |> Enum.all?(fn ch -> ch in ?A..?Z or ch in ?a..?z or ch in ?0..?9 or ch == ?- end)
  end
end
