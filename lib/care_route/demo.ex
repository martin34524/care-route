defmodule CareRoute.Demo do
  @moduledoc """
  Resetting demo data between rehearsals. Used by `mix care_route.demo_reset`
  locally and by `CareRoute.Release.demo_reset/0` in a deployed release.
  """

  import Ecto.Query

  alias CareRoute.Repo
  alias CareRoute.Intake.{Conversation, Patient}
  alias CareRoute.Referrals.Referral

  @doc "What a reset would delete."
  def counts do
    %{
      patients: Repo.aggregate(Patient, :count),
      conversations: Repo.aggregate(Conversation, :count),
      referrals: Repo.aggregate(Referral, :count),
      jobs: Repo.aggregate(Oban.Job, :count)
    }
  end

  def describe(counts) do
    "#{counts.patients} patients, #{counts.conversations} conversations, " <>
      "#{counts.referrals} referrals and #{counts.jobs} AI jobs"
  end

  @doc """
  Deletes all patients (conversations, reports, recommendations and referrals
  cascade from them) and queued jobs, then reseeds facilities and clinicians.
  Returns what was deleted.
  """
  def reset! do
    counts = counts()

    Repo.transaction(fn ->
      Repo.delete_all(Oban.Job)
      Repo.delete_all(from(p in Patient))
    end)

    Code.eval_file(Path.join(:code.priv_dir(:care_route), "repo/seeds.exs"))
    counts
  end
end
