# Copyright 2022, Phillip Heller
#
# This file is part of StageUtil.
#
# StageUtil is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# StageUtil is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
# the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with StageUtil. If not,
# see <https://www.gnu.org/licenses/>.

defmodule ObjectUtil.ObjectFile do
  require Logger
  import ExPrintf
  import Jason

  @object_type_map %{0x00 => "Page Format Object",
                     0x04 => "Page Template Object",
                     0x08 => "Page Element Object",
                     0x0C => "Program Object",
                     0x0E => "Window Object"}

  @unknown "Unknown"

  defstruct [:prologue]

  def run(source, command, %{} = args \\ %{}) do
    # TODO implement better approach to endian support, perhaps by calculating and comparing checksums
    try do
      case command do
        :dir -> object_dir(source, args)
        :info -> object_info(source)
        _ -> ObjectUtil.CLI.usage(:terse, "Command #{command} not implemented.")
      end
    rescue
      e in Error -> ObjectUtil.CLI.usage(:terse, "Error #{e}")
    end
  end

  def object_dir(source, args) do
    IO.puts(
      String.trim("""
      Source directory: #{source}

      Name             Type
      ---------------  --------------------
      """)
    )

    bytype = Map.get(args, :bytype, false)
    sort_fn = if bytype, do: &type_sort/2, else: &name_sort/2

    file_types =
      get_file_paths(source)
      |> paths_to_types
      |> Enum.sort(&(sort_fn.(&1, &2)))

    Enum.each(file_types, fn line ->
      printf("%-17s%s\n", [elem(line, 0), elem(line, 1)])
    end)
    # IO.inspect file_types
  end

  defp get_file_paths(source) do
    File.ls(source)
    |> elem(1)
    |> Enum.reject(fn f -> String.starts_with?(f, ".") end)
    |> Enum.map(fn f -> Path.join([source, f]) end)
    |> Enum.reject(fn f -> File.stat!(f).type == :directory end)
  end

  defp paths_to_types(file_paths) do
    path_to_type(file_paths, [])
  end

  defp name_sort(t1, t2) do
    elem(t1, 0) <= elem(t2, 0)
  end

  defp type_sort(t1, t2) do
    case (elem(t1, 1) == elem(t2, 1)) do
      true -> name_sort(t1, t2)
      _ -> elem(t1, 1) <= elem(t2, 1)
    end
  end

  defp path_to_type([], type_list) do
    type_list
  end

  defp path_to_type([phead | ptail], type_list) do
    with {:ok, file} <- File.open(phead),
        data <- IO.binread(file, :eof),
         :ok <- File.close(file) do
      # Do something with the contents of the file
      <<
        name::binary-size(8),
        ext::binary-size(3),
        _sequence,
        type,
        _rest::binary
      >> = data

      filename = String.trim(name) <> "." <> String.trim(ext)
      object_type = Map.get(@object_type_map, type, @unknown)

      result = case object_type do
        @unknown -> type_list
        _ -> [{filename, object_type} | type_list]
      end

      path_to_type(ptail, result)
    else
      {:error, reason} ->
        # Handle the case where the file couldn't be opened or read
        IO.puts("Error: #{reason}")
        :error
    end
  end

  def object_info(source) do
    with {:ok, file} <- File.open(source),
        data <- IO.binread(file, :eof),
         :ok <- File.close(file) do
      # Do something with the contents of the file

      os_list = ObjectTypes.parse_buffer(data)

      IO.inspect(os_list)

      json_list = Jason.encode!(os_list)
      IO.inspect(json_list)
    else
      {:error, reason} ->
        # Handle the case where the file couldn't be opened or read
        IO.puts("Error: #{reason}")
        :error
    end
  end

  defmodule Dir do
    def pre(source, _endian, _prologue) do
      IO.puts(
        String.trim("""
        Source: #{source}

        Name          Seq Type # in Set Length Version Storage     Version Check
        ------------  --- ---- -------- ------ ------- ----------- -------------
        """)
      )
    end

    def each(filename, sequence, type, length, setsize, candidacy, version, _data, _args) do
      candidacy_str =
        case candidacy do
          0 -> "Cache"
          1 -> "None"
          2 -> "Stage"
          3 -> "Stage"
          4 -> "Required"
          5 -> "Required"
          6 -> "Large Stage"
          7 -> "Large Stage"
        end

      version_check = if candidacy in [3, 5, 6], do: "No", else: "Yes"

      IO.puts(
        sprintf("%-12s  %3d %4x %8d %6d %7d %-11s %-3s", [
          filename,
          sequence,
          type,
          setsize,
          length,
          version,
          candidacy_str,
          version_check
        ])
      )
    end

    def post do
    end
  end

  defmodule Export do
    def pre(_source, _endian, _prologue) do
    end

    def each(filename, _sequence, _type, length, _setsize, _candidacy, _version, data, args) do
      case File.open(Path.join(args.target, filename), [:write]) do
        {:ok, out} ->
          IO.binwrite(out, binary_part(data, 0, length))
          File.close(out)

        {:error, :eilseq} ->
          IO.puts("ERROR: illegal filename '#{inspect(filename, base: :hex)}'")
      end
    end

    def post do
    end
  end

  defmodule Info do
    def pre(source, endian, prologue) do
      IO.puts("""
      Source: #{source}

                Endian: #{endian}
       Structure level: #{prologue.structure_level}
           Quanta Size: #{prologue.au_quanta_size}
             Map Width: #{prologue.map_width}
       Max Map Entries: #{prologue.max_map_entries}
      Directory length: #{prologue.dir_total_byte_size}
      """)
    end

    def each(_filename, _sequence, _type, _length, _setsize, _candidacy, _version, _data, _args) do
    end

    def post do
    end
  end

  defp open(source, action, endian, args) do
    {:ok, file} = File.open(source)
    # {:ok, prologue} = StageUtil.Prologue.decode(file, endian)

    action =
      case action do
        :dir -> Dir
        :export -> Export
        :info -> Info
        _ -> nil
      end

    # The map and directory is duplicated for reliability, but only the first entries are read here for simplicity
    # aum0 = Aum.decode(file, prologue, Enum.at(prologue.start_ids, 0).map_start_id)
    # dir0 = Aum.read_directory(endian, file, prologue, aum0, Enum.at(prologue.start_ids, 0).dir_start_id)
    #
    # action.pre(source, endian, prologue)
    #
    # Enum.each(dir0.entries, fn entry ->
    #   try do
    #     data = Aum.read_chain(file, prologue, aum0, entry.startid)
    #     case byte_size(data) < entry.length do
    #       true ->
    #         IO.puts("ERROR: #{entry.filename} is corrupt (not enough allocation units for specified filesize)")
    #       false ->
    #         Object.parse_object(binary_part(data, 0, entry.length), &action.each/9, args)
    #     end
    #   rescue
    #     _e in RuntimeError ->
    #       IO.puts("ERROR: #{entry.filename} is corrupt (reached end of STAGE.DAT before end of file)")
    #   end
    # end)
  end
end
