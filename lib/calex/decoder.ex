defmodule Calex.Decoder do
  @moduledoc false

  alias Calex.{DecodeError, InvalidTimeZoneError}

  # https://rubular.com/r/sXPKG84KfgtfMV
  @utc_datetime_pattern ~r/^\d{8}T\d{6}Z$/
  @local_datetime_pattern ~r/^\d{8}T\d{6}$/
  @date_pattern ~r/^\d{8}$/

  # Should probably make this more robust
  @duration_pattern ~r/^P.*$/

  @gmt_offset_pattern ~r/^GMT(\+|\-)(\d{2})(\d{2})$/

  def decode!(data) do
    data
    |> decode_lines()
    |> decode_blocks()
  end

  defp decode_lines(bin) do
    bin
    |> String.splitter(["\r\n", "\n"])
    |> Enum.flat_map_reduce(nil, fn
      " " <> rest, acc ->
        {[], acc <> rest}

      line, prevline ->
        {(prevline && [prevline]) || [], line}
    end)
    |> elem(0)
  end

  defp decode_blocks([]), do: []

  # decode each block as a list
  defp decode_blocks(["BEGIN:" <> binkey | rest]) do
    {props, [_ | lines_rest]} = Enum.split_while(rest, &(!match?("END:" <> ^binkey, &1)))
    key = decode_key(binkey)

    # accumulate block of same keys
    case decode_blocks(lines_rest) do
      [{^key, elems} | props_rest] -> [{key, [decode_blocks(props) | elems]} | props_rest]
      props_rest -> [{key, [decode_blocks(props)]} | props_rest]
    end
  end

  # recursive decoding if no BEGIN/END block
  defp decode_blocks([prop | rest]), do: [decode_prop(prop) | decode_blocks(rest)]

  # decode key,params and value for each prop
  defp decode_prop(prop) do
    case split_content_line(prop) do
      ["", _prop_val] ->
        raise DecodeError, message: "property key missing or blank line"

      [prop_key, ""] ->
        raise DecodeError, message: "property has no value: #{inspect(prop_key)}"

      [prop_key, prop_val] ->
        case prop_key do
          "DURATION" -> {:duration, {decode_duration(prop_val), []}}
          prop_key -> {decode_key(prop_key), {decode_value(prop_val, []), []}}
        end

      [prop_key | params_and_prop_val] ->
        {raw_params, [prop_val]} = Enum.split(params_and_prop_val, -1)

        params =
          raw_params
          |> Enum.map(fn raw_param ->
            [k, v] = String.split(raw_param, "=", parts: 2)

            {decode_key(k), v}
          end)

        {decode_key(prop_key), {decode_value(prop_val, params), params}}
    end
  end

  defp split_content_line(line),
    do: split_content_line(line, "", [], false)

  # Following parses on a byte-by-byte basis.  This works because multi-byte
  # UTF-8 won't contain these characters (ASCII starts with a 0 bit while all
  # other UTF-8 bytes start with a 1 bit)
  defp split_content_line("", char_acc, list_acc, _in_quotes),
    do: ["" | [char_acc | list_acc]] |> Enum.reverse()

  defp split_content_line(<<"\"", rest::binary>>, char_acc, list_acc, in_quotes),
    do: split_content_line(rest, char_acc, list_acc, not in_quotes)

  defp split_content_line(<<":", rest::binary>>, char_acc, list_acc, false = _in_quotes),
    do: [rest | [char_acc | list_acc]] |> Enum.reverse()

  defp split_content_line(<<";", rest::binary>>, char_acc, list_acc, false = in_quotes),
    do: split_content_line(rest, "", [char_acc | list_acc], in_quotes)

  defp split_content_line(<<char, rest::binary>>, char_acc, list_acc, in_quotes),
    do: split_content_line(rest, char_acc <> <<char>>, list_acc, in_quotes)

  defp decode_value(val, props) do
    time_zone = Keyword.get(props, :tzid)

    cond do
      String.match?(val, @local_datetime_pattern) ->
        decode_local_datetime(val, time_zone)

      String.match?(val, @utc_datetime_pattern) ->
        decode_utc_datetime(val)

      String.match?(val, @date_pattern) && Keyword.get(props, :value) == "DATE" ->
        decode_date(val)

      String.match?(val, @duration_pattern) && Keyword.get(props, :value) == "DURATION" ->
        decode_duration(val)

      true ->
        unescape_prop_value(val)
    end
  end

  defp unescape_prop_value(val) do
    val
    |> String.replace(~r/\\(\\|;|,|N|n)/, fn
      "\\\\" -> "\\"
      "\\;" -> ";"
      "\\," -> ","
      "\\N" -> "\n"
      "\\n" -> "\n"
    end)
  end

  defp decode_local_datetime(val, time_zone) do
    naive_datetime = Timex.parse!(val, "{YYYY}{0M}{0D}T{h24}{m}{s}")

    if time_zone do
      case Regex.run(@gmt_offset_pattern, time_zone) do
        [_, "-", hour, min] ->
          naive_datetime
          |> DateTime.from_naive!("Etc/UTC")
          |> Timex.add(String.to_integer(hour) |> Timex.Duration.from_hours())
          |> Timex.add(String.to_integer(min) |> Timex.Duration.from_minutes())
          |> DateTime.truncate(:second)

        [_, "+", hour, min] ->
          naive_datetime
          |> DateTime.from_naive!("Etc/UTC")
          |> Timex.subtract(String.to_integer(hour) |> Timex.Duration.from_hours())
          |> Timex.subtract(String.to_integer(min) |> Timex.Duration.from_minutes())
          |> DateTime.truncate(:second)

        _ ->
          if !Enum.member?(Tzdata.zone_list(), time_zone) do
            raise InvalidTimeZoneError,
              message: "#{time_zone} is not a valid time zone identifier"
          end

          naive_datetime
          |> DateTime.from_naive!(time_zone)
          |> DateTime.truncate(:second)
      end
    else
      naive_datetime
    end
  end

  defp decode_utc_datetime(val) do
    val
    |> Timex.parse!("{YYYY}{0M}{0D}T{h24}{m}{s}Z")
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp decode_date(val) do
    val
    |> Timex.parse!("{YYYY}{0M}{0D}")
    |> NaiveDateTime.to_date()
  end

  defp decode_key(bin) do
    bin
    |> String.replace("-", "_")
    |> String.downcase()
    |> String.slice(0..254)
    |> String.to_atom()
  end

  defp decode_duration(val) do
    case Timex.Duration.parse(val) do
      {:ok, duration} -> duration
      _ -> val
    end
  end
end
