defmodule CareRoute.Repo.Migrations.UniqueReferralPerConversation do
  use Ecto.Migration

  # One referral per intake: two tabs or a double tap can't create a second one.
  def change do
    create unique_index(:referrals, [:conversation_id])
  end
end
