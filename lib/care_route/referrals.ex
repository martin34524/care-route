defmodule CareRoute.Referrals do
  @moduledoc """
  Referral records and live notifications to clinicians.
  """

  import Ecto.Query
  alias CareRoute.Repo
  alias CareRoute.Referrals.Referral

  @topic "referrals"

  def subscribe, do: Phoenix.PubSub.subscribe(CareRoute.PubSub, @topic)

  def list_referrals do
    Repo.all(
      from r in Referral, order_by: [desc: r.inserted_at], preload: [:patient, :to_facility]
    )
  end

  def get_referral!(id) do
    Referral
    |> Repo.get!(id)
    |> Repo.preload([:patient, :conversation, :from_facility, :to_facility])
  end

  @doc "Creates a referral and broadcasts `{:referral_created, referral}` to clinicians."
  def create_referral(attrs) do
    with {:ok, referral} <- %Referral{} |> Referral.changeset(attrs) |> Repo.insert() do
      referral = Repo.preload(referral, [:patient, :to_facility])
      Phoenix.PubSub.broadcast(CareRoute.PubSub, @topic, {:referral_created, referral})
      {:ok, referral}
    end
  end

  def update_referral(%Referral{} = referral, attrs) do
    with {:ok, referral} <- referral |> Referral.changeset(attrs) |> Repo.update() do
      referral = Repo.preload(referral, [:patient, :to_facility], force: true)
      Phoenix.PubSub.broadcast(CareRoute.PubSub, @topic, {:referral_updated, referral})
      {:ok, referral}
    end
  end
end
