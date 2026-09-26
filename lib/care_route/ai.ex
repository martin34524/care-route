defmodule CareRoute.AI do
  @moduledoc """
  Single entry point for structured AI calls.

  Every call site describes its output as a tool (`name` + JSON `input_schema`)
  and passes an offline stub. The provider is picked by which key is set:
  Gemini, then Claude, then the stub — so the whole app runs without keys.

  Backup plan for a live demo:
    * If Gemini fails and an Anthropic key is also set, the call is retried on Claude.
    * `AI_PROVIDER=gemini|claude|stub` (config `:ai_provider`) forces a provider,
      e.g. `stub` to keep the demo running when the network or AI service is down.
  """

  alias CareRoute.AI.{Claude, Gemini}

  require Logger

  @doc """
  A short, log-safe description of a provider error response: the error type
  and a truncated message, never the full body (which can echo request data).
  """
  def error_summary(%{"error" => %{} = error}) do
    type = error["status"] || error["type"] || error["code"]
    message = error["message"] |> to_string() |> String.slice(0, 160)
    String.trim("#{type} #{message}")
  end

  def error_summary(_body), do: "unexpected response"

  def provider do
    cond do
      forced = Application.get_env(:care_route, :ai_provider) -> forced
      Gemini.configured?() -> :gemini
      Claude.configured?() -> :claude
      true -> :stub
    end
  end

  @doc "Returns `{:ok, map}` matching `tool[\"input_schema\"]`, or `{:error, reason}`."
  def generate(system, messages, %{"input_schema" => schema} = tool, stub_fun)
      when is_function(stub_fun, 0) do
    case Process.get(:care_route_ai_result) do
      nil -> call(provider(), system, messages, tool, schema, stub_fun)
      # Test seam: `Process.put(:care_route_ai_result, {:error, :timeout})`.
      result -> result
    end
  end

  defp call(provider, system, messages, tool, schema, stub_fun) do
    case provider do
      :gemini ->
        with {:error, reason} <- Gemini.generate_json(system, messages, schema) do
          if Claude.configured?() do
            Logger.warning("Gemini failed (#{inspect(reason)}); retrying on Claude")
            Claude.call_tool(system, messages, tool)
          else
            {:error, reason}
          end
        end

      :claude ->
        Claude.call_tool(system, messages, tool)

      :stub ->
        {:ok, stub_fun.()}
    end
  end
end
