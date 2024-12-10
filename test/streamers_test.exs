defmodule StreamersTest do
  use ExUnit.Case, async: true
  doctest Streamers

  @index_file "test/fixtures/emberjs/9af0270acb795f9dcafb5c51b1907628.m3u8"

  test "greets the world" do
    assert Streamers.hello() == :world
  end

  test "find index file in a directory" do
    assert Streamers.find_index("test/fixtures/emberjs") == @index_file
  end

  test "return nil for non available index file" do
    assert Streamers.find_index("test/fixtures/not_available") == nil
  end

  test "extracts m3u8 from index file" do
    m3u8 = Streamers.extract_m3u8(@index_file)

    assert List.first(m3u8) ==
             Streamers.m3u8(
               program_id: 1,
               bandwidth: 110_000,
               path: "test/fixtures/emberjs/8bda35243c7c0a7fc69ebe1383c6464c.m3u8"
             )

    assert length(m3u8) == 5
  end

  test "process m3u8" do
    m3u8 = @index_file |> Streamers.extract_m3u8() |> Streamers.process_m3u8()
    first = List.first(m3u8)
    assert first |> is_tuple()
    ts_files = Streamers.m3u8(first, :ts_files)
    assert length(ts_files) == 510
  end
end
