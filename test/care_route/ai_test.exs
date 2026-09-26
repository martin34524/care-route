defmodule CareRoute.AITest do
  use ExUnit.Case, async: true

  alias CareRoute.AI

  test "error summaries keep the type and a short message, not the body" do
    gemini = %{
      "error" => %{
        "code" => 503,
        "status" => "UNAVAILABLE",
        "message" => "This model is currently experiencing high demand.",
        "details" => [%{"echo" => "patient says: chest pain"}]
      }
    }

    summary = AI.error_summary(gemini)
    assert summary == "UNAVAILABLE This model is currently experiencing high demand."
    refute summary =~ "chest pain"

    claude = %{
      "type" => "error",
      "error" => %{"type" => "overloaded_error", "message" => "Overloaded"}
    }

    assert AI.error_summary(claude) == "overloaded_error Overloaded"

    assert AI.error_summary(%{"error" => %{"message" => String.duplicate("x", 500)}})
           |> String.length() == 160

    assert AI.error_summary("<html>bad gateway</html>") == "unexpected response"
  end
end
