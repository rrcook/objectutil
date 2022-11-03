# Copyright 2022, Phillip Heller
#
# This file is part of ObjectUtil.
#
# ObjectUtil is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# ObjectUtil is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
# the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with ObjectUtil. If not,
# see <https://www.gnu.org/licenses/>.

defmodule ObjectUtil.Object do
  import ExMinimatch
  import Logger

  def parse_object(data, action \\ nil, args \\ %{}, level \\ 0) do
    <<
      name::binary-size(8),
      ext::binary-size(3),
      sequence,
      type,
      length::16-little,
      candidacy_version_high,
      set_size,
      candidacy_version_low,
      rest::binary
    >> = data

    <<candidacy::3, version::13>> = <<candidacy_version_high, candidacy_version_low>>
    << candidacy_int::8-big >> = << 0::5, candidacy::3 >>
    << version_int::16-big >> = << 0::3, version::13 >>

    filename = String.trim(name) <> "." <> String.trim(ext)

    if match(Map.get(args, :glob, "*"), filename) and action != nil, do: action.(filename, sequence, type, length, set_size, candidacy_int, version_int, data, args)

    try do
      if args.recurse, do: parse_segment(rest, action, args, level)
    rescue
      _ in MatchError ->
        Logger.warn("bad segments in #{filename}")
        throw {:invalid_segment, type}
    catch
      {:invalid_segment, type} ->
        Logger.warn("invalid segment type #{type} in #{filename}")
        throw {:invalid_segment, type}

    end
  end

  defp parse_segment(<<type, length::16-little, rest::binary>>, action, args, level) do
    if type not in [0x01, 0x02, 0x03, 0x04, 0x0a, 0x0b, 0x0e, 0x10, 0x20, 0x21, 0x26, 0x27, 0x31, 0x33, 0x51, 0x52,
      0x61, 0x62, 0x63, 0x64, 0x71], do: throw({:invalid_segment, type})
    data_length = length - 3
    <<data::binary-size(data_length), excess::binary>> = rest
    # type 0x52 == embedded object
    if type == 0x52, do: parse_object(data, action, args, level + 1)
    parse_segment(excess, action, args, level + 1)
  end

  defp parse_segment(<<>>, _action, _args, _level) do
  end
end
