defmodule CareRoute.SafetyTest do
  use ExUnit.Case, async: true

  alias CareRoute.Safety

  test "unmistakable danger phrases are red flags, in English and Kiswahili" do
    assert {:red_flags, ["chest pain"]} =
             Safety.screen("My father has chest pain spreading to his arm")

    assert {:red_flags, ["difficulty breathing"]} = Safety.screen("She can’t breathe properly")
    assert {:red_flags, ["seizure"]} = Safety.screen("Mtoto ana degedege")

    assert {:red_flags, ["possible stroke signs"]} =
             Safety.screen("his face drooping and slurred speech")

    assert {:red_flags, ["possible poisoning or overdose"]} = Safety.screen("He drank paraffin")

    assert {:red_flags, ["bleeding or severe pain in pregnancy"]} =
             Safety.screen("I'm 6 months pregnant and I've started bleeding")
  end

  test "negated danger signs don't count" do
    assert :ok = Safety.screen("No chest pain and no difficulty breathing")
    assert :ok = Safety.screen("She doesn't have trouble breathing, she's playing")
    assert :ok = Safety.screen("no fever, cough or chest pain")
    assert :ok = Safety.screen("Hana shida ya kupumua")
  end

  test "a negation doesn't reach past 'but' or into another sentence" do
    assert {:red_flags, _} = Safety.screen("No fever but now chest pain")
    assert {:red_flags, _} = Safety.screen("No cough. Chest pain since morning.")
  end

  test "ordinary answers pass" do
    assert :ok = Safety.screen("My 3-year-old has had a fever for two days")
    assert :ok = Safety.screen("She's drinking well and breathing normally")
    # Whole words only.
    assert :ok = Safety.screen("I had heatstroke last year")
    assert :ok = Safety.screen("Ninahisi uchovu tu")
  end

  test "possible self-harm is a crisis, even when phrased with a negation" do
    assert :crisis = Safety.screen("I want to end my life")
    assert :crisis = Safety.screen("sometimes I think about suicide")
    assert :crisis = Safety.screen("Nataka kujiua")
    assert :crisis = Safety.screen("I don't want to kill myself but I feel hopeless")
  end
end
