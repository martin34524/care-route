defmodule CareRoute.Intake.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(gathering urgent assessed)a

  schema "conversations" do
    # Random, unguessable id used in patient URLs instead of the sequential id.
    field :token, :string
    field :status, Ecto.Enum, values: @statuses, default: :gathering
    field :transcript, {:array, :map}, default: []

    belongs_to :patient, CareRoute.Intake.Patient
    has_one :symptom_report, CareRoute.Intake.SymptomReport
    has_one :care_recommendation, CareRoute.Routing.CareRecommendation

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:patient_id, :status, :transcript])
    |> put_token()
    |> validate_required([:patient_id, :status, :token])
    |> unique_constraint(:token)
    |> foreign_key_constraint(:patient_id)
  end

  defp put_token(%Ecto.Changeset{data: %{token: nil}} = changeset) do
    put_change(
      changeset,
      :token,
      :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    )
  end

  defp put_token(changeset), do: changeset
end
