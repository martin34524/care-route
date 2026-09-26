defmodule CareRoute.Referrals do
  @moduledoc """
  Referral records and live notifications to clinicians.
  """

  import Ecto.Query
  alias CareRoute.Repo
  alias CareRoute.Referrals.Referral
  alias CareRoute.Workers.HandoffWorker

  @topic "referrals"

  # Everything the clinician dashboard shows; broadcasts carry the same shape.
  @preloads [:patient, :to_facility, conversation: [:care_recommendation, :symptom_report]]

  def subscribe, do: Phoenix.PubSub.subscribe(CareRoute.PubSub, @topic)

  @doc "Referrals, newest first. `facility_id: id` limits them to one receiving facility."
  def list_referrals(opts \\ []) do
    Referral
    |> filter_facility(opts[:facility_id])
    |> order_by(desc: :inserted_at)
    |> Repo.all()
    |> Repo.preload(@preloads)
  end

  defp filter_facility(query, nil), do: query
  defp filter_facility(query, facility_id), do: where(query, to_facility_id: ^facility_id)

  def get_referral!(id) do
    Referral
    |> Repo.get!(id)
    |> Repo.preload([:from_facility | @preloads])
  end

  @doc "The referral made from a conversation, if any."
  def get_referral_for_conversation(conversation_id) do
    Referral
    |> where(conversation_id: ^conversation_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload([:patient, :to_facility])
  end

  @doc """
  Creates a referral, enqueues its AI handoff summary, and broadcasts
  `{:referral_created, referral}` to clinicians.
  """
  def create_referral(attrs) do
    # The referral and its summary job are saved together, so a referral can
    # never exist without a summary job (or vice versa).
    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:referral, Referral.changeset(%Referral{}, attrs))
      |> Oban.insert(:job, fn %{referral: r} -> HandoffWorker.new(%{referral_id: r.id}) end)

    case Repo.transaction(multi) do
      {:ok, %{referral: referral}} ->
        referral = Repo.preload(referral, @preloads)
        Phoenix.PubSub.broadcast(CareRoute.PubSub, @topic, {:referral_created, referral})
        {:ok, referral}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  def update_referral(%Referral{} = referral, attrs) do
    changeset =
      referral
      |> Referral.changeset(attrs)
      |> stamp_response()

    with {:ok, referral} <- Repo.update(changeset) do
      referral = Repo.preload(referral, @preloads, force: true)
      Phoenix.PubSub.broadcast(CareRoute.PubSub, @topic, {:referral_updated, referral})
      {:ok, referral}
    end
  end

  @doc "Clears a failed AI summary and queues a new attempt."
  def retry_summary(%Referral{ai_summary: nil} = referral), do: regenerate_summary(referral)
  def retry_summary(%Referral{}), do: {:error, :already_summarized}

  @doc "Discards the current AI summary (if any) and queues a fresh one."
  def regenerate_summary(%Referral{} = referral) do
    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :referral,
        Referral.changeset(referral, %{ai_summary: nil, summary_failed_at: nil})
      )
      |> Oban.insert(:job, HandoffWorker.new(%{referral_id: referral.id}))

    case Repo.transaction(multi) do
      {:ok, %{referral: referral}} ->
        referral = Repo.preload(referral, @preloads, force: true)
        Phoenix.PubSub.broadcast(CareRoute.PubSub, @topic, {:referral_updated, referral})
        {:ok, referral}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc "Sends a referral to a different facility; it goes back to pending there."
  def reassign_referral(%Referral{} = referral, facility_id) do
    update_referral(referral, %{to_facility_id: facility_id, status: :pending})
  end

  # The first move out of :pending records how long the referral waited.
  defp stamp_response(%Ecto.Changeset{data: %{responded_at: nil}} = changeset) do
    if Ecto.Changeset.get_change(changeset, :status) in [:accepted, :completed],
      do: Ecto.Changeset.put_change(changeset, :responded_at, DateTime.utc_now(:second)),
      else: changeset
  end

  defp stamp_response(changeset), do: changeset

  @doc """
  Dashboard numbers, optionally for one facility: referrals received today,
  average minutes to first response, and patients with an open referral.
  """
  def stats(opts \\ []) do
    base = filter_facility(Referral, opts[:facility_id])
    today = local_midnight(opts[:now] || DateTime.utc_now())

    avg_seconds =
      base
      |> where([r], not is_nil(r.responded_at))
      |> select([r], avg(fragment("EXTRACT(EPOCH FROM (? - ?))", r.responded_at, r.inserted_at)))
      |> Repo.one()

    %{
      new_today: base |> where([r], r.inserted_at >= ^today) |> Repo.aggregate(:count),
      avg_response_minutes: avg_seconds && round(to_float(avg_seconds) / 60),
      active_patients:
        base
        |> where([r], r.status != :completed)
        |> select([r], count(r.patient_id, :distinct))
        |> Repo.one()
    }
  end

  @doc "The start of the local day containing `now`, as a UTC datetime."
  def local_midnight(%DateTime{} = now) do
    offset = Application.fetch_env!(:care_route, :utc_offset_seconds)

    now
    |> DateTime.add(offset)
    |> DateTime.to_date()
    |> DateTime.new!(~T[00:00:00])
    |> DateTime.add(-offset)
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n), do: n / 1

  @doc "Per-facility referral load: `[%{facility: name, type: type, pending: n, total: n}]`."
  def load_by_facility do
    Repo.all(
      from f in CareRoute.Facilities.Facility,
        left_join: r in Referral,
        on: r.to_facility_id == f.id,
        group_by: [f.id, f.name, f.type],
        order_by: [desc: count(r.id), asc: f.name],
        select: %{
          id: f.id,
          facility: f.name,
          type: f.type,
          pending: filter(count(r.id), r.status == :pending),
          total: count(r.id)
        }
    )
  end
end
