defmodule CareRoute.RetentionWorkerTest do
  use CareRoute.DataCase, async: true
  use Oban.Testing, repo: CareRoute.Repo

  alias CareRoute.{Intake, Repo}
  alias CareRoute.Intake.{Conversation, Patient}
  alias CareRoute.Workers.RetentionWorker

  test "deletes patients past the retention period with their conversations" do
    {:ok, old} = Intake.create_patient(%{name: "Old"})
    {:ok, _} = Intake.start_conversation(old)
    {:ok, recent} = Intake.create_patient(%{name: "Recent"})
    {:ok, _} = Intake.start_conversation(recent)

    long_ago = DateTime.add(DateTime.utc_now(:second), -31 * 24 * 60 * 60)
    old |> Ecto.Changeset.change(inserted_at: long_ago) |> Repo.update!()

    assert :ok = perform_job(RetentionWorker, %{})

    assert [%{name: "Recent"}] = Repo.all(Patient)
    assert Repo.aggregate(Conversation, :count) == 1
  end

  test "is scheduled daily" do
    crontab =
      Application.fetch_env!(:care_route, Oban)[:plugins] |> Keyword.fetch!(Oban.Plugins.Cron)

    assert {"0 3 * * *", RetentionWorker} in crontab[:crontab]
  end
end
