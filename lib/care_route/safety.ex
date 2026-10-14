defmodule CareRoute.Safety do
  @moduledoc """
  Deterministic safety net that runs on every patient message before the AI.

  The AI is the main red-flag detector, but it can miss a danger sign (an odd
  phrasing, a garbled voice answer, an outage). Unmistakable phrases in English
  or Kiswahili escalate straight to urgent care here, whatever the AI would say.

  Matches are whole words or phrases. A red-flag phrase preceded in the same
  clause by a negation ("no chest pain", "hana shida ya kupumua") doesn't count.
  Self-harm phrases always count, negated or not: a false alarm there costs a
  kind message, a miss could cost a life.
  """

  # {category, English label for clinicians, phrases (English and Kiswahili)}
  @red_flags [
    {:breathing, "difficulty breathing",
     [
       "difficulty breathing",
       "trouble breathing",
       "hard to breathe",
       "can't breathe",
       "cannot breathe",
       "cant breathe",
       "unable to breathe",
       "not breathing",
       "struggling to breathe",
       "struggling for breath",
       "gasping",
       "choking",
       "lips are blue",
       "blue lips",
       "turning blue",
       "shida ya kupumua",
       "anashindwa kupumua",
       "hawezi kupumua",
       "siwezi kupumua",
       "hapumui",
       "kubanwa na pumzi",
       "midomo ya bluu"
     ]},
    {:chest_pain, "chest pain",
     [
       "chest pain",
       "chest pains",
       "pain in my chest",
       "pain in his chest",
       "pain in her chest",
       "chest pressure",
       "chest tightness",
       "tight chest",
       "maumivu ya kifua",
       "maumivu kifuani",
       "kifua kinauma",
       "kifua kinaniuma"
     ]},
    {:unconscious, "loss of consciousness",
     [
       "unconscious",
       "unresponsive",
       "passed out",
       "fainted",
       "collapsed",
       "won't wake up",
       "can't wake",
       "cannot wake",
       "kupoteza fahamu",
       "amepoteza fahamu",
       "amezimia",
       "kuzimia",
       "haamki"
     ]},
    {:seizure, "seizure",
     [
       "seizure",
       "seizures",
       "seizing",
       "convulsion",
       "convulsions",
       "convulsing",
       "degedege",
       "kifafa"
     ]},
    {:stroke, "possible stroke signs",
     [
       "stroke",
       "face drooping",
       "face is drooping",
       "drooping face",
       "slurred speech",
       "slurring",
       "can't move one side",
       "weakness on one side",
       "numb on one side",
       "kiharusi",
       "kupooza upande mmoja"
     ]},
    {:bleeding, "severe bleeding",
     [
       "heavy bleeding",
       "severe bleeding",
       "bleeding heavily",
       "bleeding a lot",
       "won't stop bleeding",
       "wont stop bleeding",
       "vomiting blood",
       "coughing up blood",
       "damu nyingi",
       "kutapika damu",
       "anatapika damu",
       "kukohoa damu"
     ]},
    {:allergy, "possible severe allergic reaction",
     [
       "throat is closing",
       "throat closing",
       "throat swelling",
       "swollen throat",
       "tongue is swelling",
       "swollen tongue",
       "anaphylaxis",
       "severe allergic",
       "ulimi umevimba",
       "koo limevimba"
     ]},
    {:poisoning, "possible poisoning or overdose",
     [
       "overdose",
       "overdosed",
       "poisoned",
       "poisoning",
       "swallowed poison",
       "drank poison",
       "rat poison",
       "took too many pills",
       "drank paraffin",
       "drank bleach",
       "sumu",
       "amekunywa sumu",
       "amemeza sumu"
     ]}
  ]

  # Two things mentioned together that are a red flag only in combination.
  @combined [
    {:pregnancy, "bleeding or severe pain in pregnancy",
     ["pregnant", "pregnancy", "mjamzito", "ujauzito", "mimba"],
     ["bleeding", "bleed", "severe pain", "damu", "maumivu makali"]}
  ]

  @crisis [
    "suicide",
    "suicidal",
    "kill myself",
    "killing myself",
    "end my life",
    "end it all",
    "take my own life",
    "want to die",
    "wanna die",
    "better off dead",
    "no reason to live",
    "hurt myself",
    "harm myself",
    "harming myself",
    "self harm",
    "self-harm",
    "cut myself",
    "kill himself",
    "kill herself",
    "end his life",
    "end her life",
    "kujiua",
    "nijiue",
    "nataka kufa",
    "kujidhuru",
    "kujiumiza",
    "kujitoa uhai"
  ]

  @negations ~w(no not never without denies deny nor neither don't doesn't didn't isn't
                aren't hasn't haven't hadn't dont doesnt didnt isnt hasnt havent
                hakuna hana sina hajapata hajawa bila)
  # A negation doesn't reach past these ("no fever but chest pain").
  @clause_breaks ~w(but however although though now lakini ila sasa)
  @negation_reach 5

  @doc """
  Screens one patient message. Returns `:ok`, `{:red_flags, labels}` with
  English labels for the clinician, or `:crisis` for possible self-harm.
  """
  def screen(text) when is_binary(text) do
    text = normalize(text)

    cond do
      Enum.any?(@crisis, &match?([_ | _], matches(text, &1))) ->
        :crisis

      (labels = red_flag_labels(text)) != [] ->
        {:red_flags, labels}

      true ->
        :ok
    end
  end

  def screen(_text), do: :ok

  defp red_flag_labels(text) do
    single =
      for {_category, label, phrases} <- @red_flags,
          Enum.any?(phrases, &affirmed?(text, &1)),
          do: label

    combined =
      for {_category, label, first, second} <- @combined,
          Enum.any?(first, &affirmed?(text, &1)),
          Enum.any?(second, &affirmed?(text, &1)),
          do: label

    single ++ combined
  end

  # The phrase appears at least once without a negation before it.
  defp affirmed?(text, phrase) do
    text |> matches(phrase) |> Enum.any?(fn {start, _len} -> not negated?(text, start) end)
  end

  defp matches(text, phrase) do
    Regex.scan(~r/(?<![\p{L}\p{N}])#{Regex.escape(phrase)}(?![\p{L}\p{N}])/u, text,
      return: :index
    )
    |> Enum.map(&hd/1)
  end

  defp negated?(text, start) do
    text
    |> binary_part(0, start)
    # Only the current sentence or clause.
    |> String.split(~r/[.;!?\n]/u)
    |> List.last()
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.reverse()
    |> Enum.take(@negation_reach)
    |> Enum.take_while(&(&1 not in @clause_breaks))
    |> Enum.any?(&(&1 in @negations))
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(["’", "‘", "`"], "'")
    |> String.replace(~r/\s+/u, " ")
  end
end
