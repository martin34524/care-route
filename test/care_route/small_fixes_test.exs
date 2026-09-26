defmodule CareRoute.SmallFixesTest do
  use ExUnit.Case, async: true

  alias CareRoute.AI.IntakeStub
  alias CareRoute.Referrals

  test "'today' starts at Kenyan midnight (21:00 UTC the day before)" do
    # 22:30 UTC on the 26th is 01:30 on the 27th in Nairobi.
    assert Referrals.local_midnight(~U[2026-09-26 22:30:00Z]) == ~U[2026-09-26 21:00:00Z]
    # 20:00 UTC on the 26th is still the 26th in Nairobi.
    assert Referrals.local_midnight(~U[2026-09-26 20:00:00Z]) == ~U[2026-09-25 21:00:00Z]
  end

  test "the offline stand-in understands Kiswahili danger words and negations" do
    reply = fn text -> IntakeStub.extract([%{"role" => "patient", "content" => text}]) end

    assert %{"next_action" => "escalate_urgent"} = reply.("Mtoto ana homa na anashindwa kupumua")
    assert %{"next_action" => "escalate_urgent"} = reply.("Nina maumivu ya kifua")
    assert %{"next_action" => "ask_question"} = reply.("Ana homa, lakini hana shida ya kupumua")
  end
end
