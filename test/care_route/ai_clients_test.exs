defmodule CareRoute.AIClientsTest do
  # Not async: the provider tests change global config (API keys, provider).
  use ExUnit.Case, async: false

  alias CareRoute.AI
  alias CareRoute.AI.{Claude, Gemini}

  @schema %{"type" => "object"}
  @tool %{"name" => "record_intake", "input_schema" => @schema}
  @messages [
    %{role: "user", content: "I have a cough"},
    %{role: "assistant", content: "Since when?"}
  ]

  defp stub(fun), do: Req.Test.stub(CareRoute.AI, fun)

  defp body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end

  defp gemini_reply(conn, map) do
    Req.Test.json(conn, %{
      "candidates" => [%{"content" => %{"parts" => [%{"text" => Jason.encode!(map)}]}}]
    })
  end

  defp error(conn, status),
    do:
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{"error" => %{"message" => "nope"}})

  describe "Gemini" do
    test "sends the system prompt, schema and roles, and decodes the JSON reply" do
      stub(fn conn ->
        assert conn.request_path =~ "/models/gemini-3.6-flash:generateContent"
        assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == ["test-key"]

        req = body(conn)
        assert req["system_instruction"]["parts"] == [%{"text" => "SYSTEM"}]
        assert req["generationConfig"]["responseJsonSchema"] == @schema
        assert Enum.map(req["contents"], & &1["role"]) == ["user", "model"]

        gemini_reply(conn, %{"next_action" => "ask_question"})
      end)

      assert {:ok, %{"next_action" => "ask_question"}} =
               Gemini.generate_json("SYSTEM", @messages, @schema, api_key: "test-key")
    end

    test "falls back to the next model when one is overloaded" do
      stub(fn conn ->
        if conn.request_path =~ "gemini-3.6-flash",
          do: error(conn, 503),
          else: gemini_reply(conn, %{"from" => conn.request_path})
      end)

      assert {:ok, %{"from" => path}} =
               Gemini.generate_json("S", @messages, @schema, api_key: "k")

      assert path =~ "gemini-3.5-flash"
    end

    test "doesn't fall back on a request error, and reports exhausted models" do
      stub(&error(&1, 400))

      assert {:error, {:http_error, 400}} =
               Gemini.generate_json("S", @messages, @schema, api_key: "k")

      stub(&error(&1, 429))

      assert {:error, {:http_error, 429}} =
               Gemini.generate_json("S", @messages, @schema, api_key: "k")
    end

    test "rejects a reply that isn't JSON" do
      stub(fn conn ->
        Req.Test.json(conn, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "hi"}]}}]})
      end)

      assert {:error, %Jason.DecodeError{}} =
               Gemini.generate_json("S", @messages, @schema, api_key: "k")
    end
  end

  describe "Claude" do
    test "forces the tool with a strict schema and returns its input" do
      stub(fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-api-key") == ["test-key"]
        assert Plug.Conn.get_req_header(conn, "anthropic-version") == ["2023-06-01"]

        req = body(conn)
        assert req["tool_choice"] == %{"type" => "tool", "name" => "record_intake"}
        assert [%{"strict" => true, "name" => "record_intake"}] = req["tools"]
        assert req["thinking"] == %{"type" => "disabled"}
        assert req["system"] == "SYSTEM"

        Req.Test.json(conn, %{
          "stop_reason" => "tool_use",
          "content" => [
            %{"type" => "tool_use", "name" => "record_intake", "input" => %{"ok" => 1}}
          ]
        })
      end)

      assert {:ok, %{"ok" => 1}} =
               Claude.call_tool("SYSTEM", @messages, @tool, api_key: "test-key")
    end

    test "reports refusals, missing tool calls and HTTP errors" do
      stub(&Req.Test.json(&1, %{"stop_reason" => "refusal", "content" => []}))
      assert {:error, :refusal} = Claude.call_tool("S", @messages, @tool, api_key: "k")

      stub(&Req.Test.json(&1, %{"stop_reason" => "end_turn", "content" => [%{"type" => "text"}]}))
      assert {:error, :no_tool_use} = Claude.call_tool("S", @messages, @tool, api_key: "k")

      stub(&error(&1, 529))
      assert {:error, {:http_error, 529}} = Claude.call_tool("S", @messages, @tool, api_key: "k")
    end
  end

  describe "provider selection (demo backup plan)" do
    setup do
      saved =
        for key <- [:gemini_api_key, :anthropic_api_key, :ai_provider],
            do: {key, Application.get_env(:care_route, key)}

      on_exit(fn ->
        for {key, value} <- saved do
          if value,
            do: Application.put_env(:care_route, key, value),
            else: Application.delete_env(:care_route, key)
        end
      end)
    end

    test "falls back from Gemini to Claude when both keys are set" do
      Application.put_env(:care_route, :gemini_api_key, "g")
      Application.put_env(:care_route, :anthropic_api_key, "a")

      stub(fn conn ->
        if conn.request_path =~ "generateContent",
          do: error(conn, 503),
          else:
            Req.Test.json(conn, %{
              "content" => [
                %{
                  "type" => "tool_use",
                  "name" => "record_intake",
                  "input" => %{"via" => "claude"}
                }
              ]
            })
      end)

      assert AI.provider() == :gemini
      assert {:ok, %{"via" => "claude"}} = AI.generate("S", @messages, @tool, fn -> :stub end)
    end

    test "AI_PROVIDER=stub forces the offline stand-in even with keys set" do
      Application.put_env(:care_route, :gemini_api_key, "g")
      Application.put_env(:care_route, :ai_provider, :stub)

      assert AI.provider() == :stub
      assert {:ok, :from_stub} = AI.generate("S", @messages, @tool, fn -> :from_stub end)
    end
  end
end
