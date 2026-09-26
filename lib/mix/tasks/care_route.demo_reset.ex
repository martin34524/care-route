defmodule Mix.Tasks.CareRoute.DemoReset do
  @shortdoc "Clears patient data and reseeds facilities before a demo rehearsal"
  @moduledoc """
  Deletes every patient (and with them all conversations, symptom reports,
  recommendations and referrals), clears queued AI jobs, then re-runs the
  facility and clinician seeds.

      mix care_route.demo_reset          # shows what would be deleted
      mix care_route.demo_reset --yes    # actually deletes it

  Refuses to run in production.
  """
  use Mix.Task

  import Ecto.Query

  alias CareRoute.Repo
  alias CareRoute.Intake.{Conversation, Patient}
  alias CareRoute.Referrals.Referral

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    if Mix.env() == :prod, do: Mix.raise("demo_reset refuses to run in production")

    counts = %{
      patients: Repo.aggregate(Patient, :count),
      conversations: Repo.aggregate(Conversation, :count),
      referrals: Repo.aggregate(Referral, :count),
      jobs: Repo.aggregate(Oban.Job, :count)
    }

    summary =
      "#{counts.patients} patients, #{counts.conversations} conversations, " <>
        "#{counts.referrals} referrals and #{counts.jobs} AI jobs"

    if "--yes" in args do
      Repo.transaction(fn ->
        Repo.delete_all(Oban.Job)
        # Referrals, conversations and everything under them cascade from patients.
        Repo.delete_all(from(p in Patient))
      end)

      Code.eval_file(Path.join(:code.priv_dir(:care_route), "repo/seeds.exs"))
      Mix.shell().info("Deleted #{summary}. Facilities and clinicians reseeded.")
    else
      Mix.shell().info("""
      This would delete #{summary}, then reseed facilities and clinicians.
      Run `mix care_route.demo_reset --yes` to do it.
      """)
    end
  end
end
