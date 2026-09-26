defmodule CareRoute.AI.Claude do
  @moduledoc """
  Minimal Anthropic Messages API client built on Req.

  `call_tool/3` forces Claude to answer by filling a single tool's JSON schema
  (`tool_choice: %{type: "tool"}` + `strict: true`), so the caller always gets
  a map matching the schema rather than free text it has to parse.
  """

  require Logger

  @api_version "2023-06-01"
  # Re-runs a safety-classifier refusal on Anthropic's recommended fallback model.
  @fallback_beta "server-side-fallback-2026-07-01"

  def configured?, do: api_key() not in [nil, ""]

  @doc """
  Sends `messages` with `system` and forces a call to `tool`.
  Returns `{:ok, tool_input_map}` or `{:error, reason}`.
  """
  def call_tool(system, messages, %{"name" => tool_name} = tool, opts \\ []) do
    body = %{
      model: Keyword.get(opts, :model, config(:model)),
      max_tokens: Keyword.get(opts, :max_tokens, 4096),
      system: system,
      messages: messages,
      tools: [Map.put(tool, "strict", true)],
      tool_choice: %{type: "tool", name: tool_name},
      # Forced tool choice requires thinking to be off.
      thinking: %{type: "disabled"},
      fallbacks: "default"
    }

    case Req.post(req(), url: "/v1/messages", json: body) do
      {:ok, %Req.Response{status: 200, body: %{"stop_reason" => "refusal"}}} ->
        {:error, :refusal}

      {:ok, %Req.Response{status: 200, body: %{"content" => content}}} ->
        case Enum.find(content, &(&1["type"] == "tool_use" and &1["name"] == tool_name)) do
          %{"input" => input} -> {:ok, input}
          nil -> {:error, :no_tool_use}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Claude API error #{status}: #{CareRoute.AI.error_summary(body)}")
        {:error, {:http_error, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp req do
    Req.new(
      base_url: config(:base_url),
      headers: [
        {"x-api-key", api_key()},
        {"anthropic-version", @api_version},
        {"anthropic-beta", @fallback_beta}
      ],
      receive_timeout: 60_000,
      # Oban owns retries/backoff for the job as a whole.
      retry: false
    )
  end

  defp api_key, do: Application.get_env(:care_route, :anthropic_api_key)
  defp config(key), do: Application.fetch_env!(:care_route, :anthropic) |> Keyword.fetch!(key)
end
