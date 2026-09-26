defmodule CareRoute.Repo.Migrations.AddConversationToken do
  use Ecto.Migration

  # Patient links use this random token instead of the sequential id, so a
  # conversation can't be opened by guessing its URL.
  def up do
    alter table(:conversations) do
      add :token, :string
    end

    flush()

    execute "UPDATE conversations SET token = replace(gen_random_uuid()::text, '-', '')"

    alter table(:conversations) do
      modify :token, :string, null: false
    end

    create unique_index(:conversations, [:token])
  end

  def down do
    alter table(:conversations) do
      remove :token
    end
  end
end
