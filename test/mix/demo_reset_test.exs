defmodule Mix.Tasks.CareRoute.DemoResetTest do
  use CareRoute.DataCase, async: false

  alias CareRoute.{Facilities, Intake, Referrals, Repo}
  alias CareRoute.Intake.Patient

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    {:ok, clinic} =
      Facilities.create_facility(%{name: "Kilimani Community Clinic", type: :clinic})

    {:ok, patient} = Intake.create_patient(%{name: "Rehearsal"})
    {:ok, conversation} = Intake.start_conversation(patient)

    {:ok, _} =
      Referrals.create_referral(%{
        patient_id: patient.id,
        conversation_id: conversation.id,
        to_facility_id: clinic.id
      })

    :ok
  end

  test "without --yes it only reports what it would delete" do
    Mix.Tasks.CareRoute.DemoReset.run([])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "would delete 1 patients, 1 conversations, 1 referrals"
    assert Repo.aggregate(Patient, :count) == 1
  end

  test "with --yes it clears patient data and reseeds facilities" do
    Mix.Tasks.CareRoute.DemoReset.run(["--yes"])

    assert Repo.aggregate(Patient, :count) == 0
    assert Referrals.list_referrals() == []
    assert Repo.aggregate(Oban.Job, :count) == 0

    names = Enum.map(Facilities.list_facilities(), & &1.name)
    assert "City General Hospital" in names
    assert length(names) == 5
    assert length(Facilities.list_clinicians()) == 2
  end
end
