defmodule CareRoute.AI.Gemini do
  @moduledoc """
  Minimal Google Gemini API client built on Req.

  `generate_json/3` uses structured output (`responseJsonSchema`), so the
  response is constrained to the given JSON schema rather than free text —
  the same guarantee `CareRoute.AI.Claude.call_tool/3` gets from forced tool use.
  """

  require Logger

  @base_url "https://generativelanguage.googleapis.com/v1beta"

  def configured?, do: api_key() not in [nil, ""]

  @doc """
  Sends `messages` (Messages-API style `%{role: "user" | "assistant", content: ...}`)
  with `system`, constrained to `schema`. Returns `{:ok, map}` or `{:error, reason}`.

  Options: `:models` overrides the configured model fallback chain; `:api_key`
  overrides the configured key.
  """
  def generate_json(system, messages, schema, opts \\ []) do
    body = %{
      system_instruction: %{parts: [%{text: system}]},
      contents: Enum.map(messages, &to_content/1),
      generationConfig: %{
        responseMimeType: "application/json",
        responseJsonSchema: schema
      }
    }

    opts
    |> Keyword.get_lazy(:models, fn -> config(:models) end)
    |> try_models(body, {:error, :no_models}, opts)
  end

  # Falls through to the next model only when the current one is overloaded.
  defp try_models([], _body, last_error, _opts), do: last_error

  defp try_models([model | rest], body, _last_error, opts) do
    case request(model, body, opts) do
      {:error, {:http_error, status}} = error when status == 429 or status >= 500 ->
        Logger.warning("Gemini #{model} unavailable (#{status}), trying next model")
        try_models(rest, body, error, opts)

      result ->
        result
    end
  end

  defp request(model, body, opts) do
    case Req.post(req(opts), url: "/models/#{model}:generateContent", json: body) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        parse_response(resp_body)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.error(
          "Gemini API error #{status} (#{model}): #{CareRoute.AI.error_summary(resp_body)}"
        )

        {:error, {:http_error, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp to_content(%{role: "assistant", content: text}),
    do: %{role: "model", parts: [%{text: text}]}

  defp to_content(%{role: "user", content: text}), do: %{role: "user", parts: [%{text: text}]}

  defp parse_response(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    case Enum.find(parts, &Map.has_key?(&1, "text")) do
      %{"text" => text} -> Jason.decode(String.trim(text))
      nil -> {:error, :no_text_part}
    end
  end

  defp parse_response(other), do: {:error, {:unexpected_response, other}}

  defp req(opts) do
    Req.new(
      base_url: @base_url,
      headers: [{"x-goog-api-key", Keyword.get(opts, :api_key, api_key())}],
      receive_timeout: 60_000,
      # Gemini returns 503 "high demand" spikes that clear within seconds; retry
      # quickly here so the chat doesn't stall on Oban's slower job backoff.
      retry: :transient,
      max_retries: 1
    )
    |> Req.merge(Application.get_env(:care_route, :ai_req_options, []))
  end

  defp api_key, do: Application.get_env(:care_route, :gemini_api_key)
  defp config(key), do: Application.fetch_env!(:care_route, :gemini) |> Keyword.fetch!(key)
end
