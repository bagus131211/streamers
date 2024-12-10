defmodule Streamers do
  require Record

  Record.defrecord(:m3u8, program_id: nil, path: nil, bandwidth: nil, ts_files: [])

  @moduledoc """
  Documentation for `Streamers`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Streamers.hello()
      :world

  """
  def hello do
    :world
  end

  @doc """
  Find streaming index file in the given directory.

      ## Examples

         iex> Streamers.find_index("test/fixtures/emberjs")
         "test/fixtures/emberjs/9af0270acb795f9dcafb5c51b1907628.m3u8"

         iex> Streamers.find_index("test/fixtures/not_available")
         nil

  """
  def find_index(directory),
    do:
      directory
      |> Path.join("*.m3u8")
      |> Path.wildcard()
      |> Enum.find(&is_index?/1)

  defp is_index?(file),
    do:
      File.open!(file, fn pid ->
        IO.read(pid, 25) == "#EXTM3U\n#EXT-X-STREAM-INF"
      end)

  @doc """
  Extract M3U8 records from the index file.

      ## Examples

         iex> Streamers.extract_m3u8("test/fixtures/emberjs/9af0270acb795f9dcafb5c51b1907628.m3u8")
         [
            {:m3u8, 1, "test/fixtures/emberjs/8bda35243c7c0a7fc69ebe1383c6464c.m3u8",
            110000, []},
            {:m3u8, 1, "test/fixtures/emberjs/3d487bf12973241be6599656fef8f8ad.m3u8",
            200000, []},
            {:m3u8, 1, "test/fixtures/emberjs/3ae4eb03047082aafe215f461fef7291.m3u8",
            350000, []},
            {:m3u8, 1, "test/fixtures/emberjs/7d06a1fce0b8dc66f477daca0516c3e0.m3u8",
            550000, []},
            {:m3u8, 1, "test/fixtures/emberjs/265c58c98c2d8b04f21ea9d7b73ee4af.m3u8",
            900000, []}
         ]

         iex> Streamers.extract_m3u8("test/fixtures/emberjs/not_available.m3u8")
         ** (File.Error) could not open "test/fixtures/emberjs/not_available.m3u8": no such file or directory

  """
  def extract_m3u8(index_file) do
    File.open!(index_file, fn pid ->
      # discard #EXTM3U
      IO.read(pid, :line)
      do_extract_m3u8(pid, Path.dirname(index_file), [])
    end)
  end

  defp do_extract_m3u8(pid, dir, acc) do
    case IO.read(pid, :line) do
      :eof ->
        Enum.reverse(acc)

      stream_inf ->
        path = IO.read(pid, :line)
        do_extract_m3u8(pid, dir, stream_inf, path, acc)
    end
  end

  defp do_extract_m3u8(pid, dir, stream_inf, path, acc) do
    <<"#EXT-X-STREAM-INF:PROGRAM-ID=", program_id, ",BANDWIDTH=", bandwidth::binary>> = stream_inf

    record =
      m3u8(
        program_id: program_id - ?0,
        path: dir |> Path.join(path |> String.trim()),
        bandwidth: bandwidth |> String.trim() |> String.to_integer()
      )

    do_extract_m3u8(pid, dir, [record | acc])
  end

  @doc """
  Process M3U8 records to get ts_files.
  """
  def process_m3u8(m3u8s) do
    m3u8s |> Enum.map(&do_parallel_process_m3u8(&1, self()))
    do_collect_m3u8(length(m3u8s), [])
  end

  defp do_collect_m3u8(0, acc), do: acc

  defp do_collect_m3u8(count, acc) do
    receive do
      {:m3u8, updated} -> do_collect_m3u8(count - 1, [updated | acc])
    end
  end

  defp do_parallel_process_m3u8(m3u8, parent_pid) do
    spawn(fn ->
      updated = do_process_m3u8(m3u8)
      send(parent_pid, {:m3u8, updated})
    end)
  end

  defp do_process_m3u8(m3u8(path: path) = record) do
    File.open!(path, fn pid ->
      # discard #EXTM3U
      IO.read(pid, :line)
      # discard #EXT-X-TARGETDURATION:15
      IO.read(pid, :line)
      m3u8(record, ts_files: do_process_m3u8(pid, []))
    end)
  end

  defp do_process_m3u8(pid, acc) do
    case IO.read(pid, :line) do
      "#EXT-X-ENDLIST\n" ->
        Enum.reverse(acc)

      extinf when is_binary(extinf) ->
        # discard #EXTINF:10,
        file = IO.read(pid, :line) |> String.trim()
        do_process_m3u8(pid, [file | acc])
    end
  end
end
