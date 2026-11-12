defmodule Cadmpeg.McpTest do
  @moduledoc """
  The server is a pure function of a message and its state, so what it answers is
  testable without a pipe: the protocol layer and the tools both.
  """

  use ExUnit.Case, async: true

  alias Cadmpeg.Mcp

  @fixture "test/fixtures/golden_simple_through_hole.step"

  defp ask(message, state \\ Mcp.fresh()) do
    {reply, state} = Mcp.handle(Jason.encode!(message), state)
    {reply && Jason.decode!(reply), state}
  end

  defp tool(name, arguments, state \\ Mcp.fresh()) do
    ask(
      %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => name, "arguments" => arguments}
      },
      state
    )
  end

  describe "the protocol" do
    test "initialize answers a version a client can speak, and names the server" do
      {reply, _state} =
        ask(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

      assert reply["result"]["protocolVersion"] in Mcp.protocol_versions()
      assert reply["result"]["serverInfo"]["name"] == "ex-cadmpeg"
    end

    test "an unknown method is an error with the method named" do
      {reply, _state} = ask(%{"jsonrpc" => "2.0", "id" => 7, "method" => "nope"})

      assert reply["error"]["code"] == -32_601
      assert reply["error"]["message"] =~ "nope"
    end

    test "a notification is answered with nothing" do
      {reply, _state} = ask(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

      assert reply == nil
    end

    test "a line that is not JSON is an error, not a crash" do
      {reply, _state} = Mcp.handle("this is not json", Mcp.fresh())

      assert Jason.decode!(reply)["error"]["code"] == -32_700
    end
  end

  describe "the tools" do
    test "the catalogue names every tool the server answers" do
      {reply, _state} = ask(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})

      names = Enum.map(reply["result"]["tools"], & &1["name"])
      assert names == ["cadmpeg_formats", "cadmpeg_inspect", "cadmpeg_convert"]

      for tool <- reply["result"]["tools"] do
        assert tool["inputSchema"]["type"] == "object"
        assert is_binary(tool["description"])
      end
    end

    test "formats says what this build reads and writes" do
      {reply, _state} = tool("cadmpeg_formats", %{})

      assert reply["result"]["isError"] == false
      assert reply["result"]["content"] |> hd() |> Map.get("text") =~ "Writes:"
      assert "step" in reply["result"]["structuredContent"]["outputs"]
    end

    test "inspect answers the decode report, losses included" do
      {reply, _state} = tool("cadmpeg_inspect", %{"path" => @fixture})

      assert reply["result"]["isError"] == false
      text = reply["result"]["content"] |> hd() |> Map.get("text")
      assert text =~ "read as step:"
      assert text =~ "geometry transferred in full"

      report = reply["result"]["structuredContent"]["report"]
      assert report["transfer"]["transfer"] == "full"
    end

    test "a second question about the same path does not read it again" do
      {_reply, state} = tool("cadmpeg_inspect", %{"path" => @fixture})
      assert Map.has_key?(state.documents, @fixture)

      {reply, state} = tool("cadmpeg_inspect", %{"path" => @fixture}, state)
      assert reply["result"]["isError"] == false
      assert map_size(state.documents) == 1
    end

    @tag :tmp_dir
    test "convert writes the file it was told to and reports what it wrote", %{tmp_dir: dir} do
      out = Path.join(dir, "converted.step")

      {reply, _state} =
        tool("cadmpeg_convert", %{"path" => @fixture, "format" => "step", "out" => out})

      assert reply["result"]["isError"] == false
      assert File.read!(out) =~ "ISO-10303-21"
      assert reply["result"]["structuredContent"]["report"]["census"]["counts"] != %{}
    end

    test "a missing argument is an error naming the argument" do
      {reply, _state} = tool("cadmpeg_inspect", %{})

      assert reply["result"]["isError"] == true
      assert reply["result"]["content"] |> hd() |> Map.get("text") == "path is required"
    end

    test "a file that cannot be read is an error with the engine's code" do
      {reply, _state} = tool("cadmpeg_inspect", %{"path" => "test/fixtures/absent.step"})

      assert reply["result"]["isError"] == true
      assert reply["result"]["content"] |> hd() |> Map.get("text") =~ "unreadable"
    end

    test "a format this build cannot write is refused by name" do
      {reply, _state} =
        tool("cadmpeg_convert", %{"path" => @fixture, "format" => "usd", "out" => "unused.usda"})

      assert reply["result"]["isError"] == true
      assert reply["result"]["content"] |> hd() |> Map.get("text") =~ "cannot write"
    end
  end
end
