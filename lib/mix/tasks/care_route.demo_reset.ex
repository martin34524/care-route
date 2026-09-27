defmodule Mix.Tasks.CareRoute.DemoReset do
  @shortdoc "Clears patient data and reseeds facilities before a demo rehearsal"
  @moduledoc """
  Deletes every patient (and with them all conversations, symptom reports,
  recommendations and referrals), clears queued AI jobs, then re-runs the
  facility and clinician seeds.

      mix care_route.demo_reset          # shows what would be deleted
      mix care_route.demo_reset --yes    # actually deletes it

  Refuses to run in production; a deployed release uses
  `CareRoute.Release.demo_reset/0` instead.
  """
  use Mix.Task

  alias CareRoute.Demo

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    if Mix.env() == :prod, do: Mix.raise("demo_reset refuses to run in production")

    if "--yes" in args do
      deleted = Demo.reset!()
      Mix.shell().info("Deleted #{Demo.describe(deleted)}. Facilities and clinicians reseeded.")
    else
      Mix.shell().info("""
      This would delete #{Demo.describe(Demo.counts())}, then reseed facilities and clinicians.
      Run `mix care_route.demo_reset --yes` to do it.
      """)
    end
  end
end
