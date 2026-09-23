defmodule CareRouteWeb.ClinicianLive.Show do
  use CareRouteWeb, :live_view

  alias CareRoute.{Intake, Referrals}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    referral = Referrals.get_referral!(id)
    conversation = referral.conversation_id && Intake.get_conversation!(referral.conversation_id)

    {:ok, assign(socket, page_title: "Referral", referral: referral, conversation: conversation)}
  end

  @impl true
  def handle_event("accept", _params, socket) do
    {:ok, referral} = Referrals.update_referral(socket.assigns.referral, %{status: :accepted})
    {:noreply, assign(socket, referral: Referrals.get_referral!(referral.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Referral for {@referral.patient.name || "Anonymous"}
        <:subtitle>{@referral.reason} · status: {@referral.status}</:subtitle>
        <:actions>
          <.button :if={@referral.status == :pending} phx-click="accept" variant="primary">
            Accept
          </.button>
        </:actions>
      </.header>

      <section class="space-y-2">
        <h3 class="font-semibold">AI handoff summary</h3>
        <p :if={@referral.ai_summary} class="whitespace-pre-line">{@referral.ai_summary}</p>
        <p :if={!@referral.ai_summary} class="opacity-60">Summary not generated yet.</p>
      </section>

      <.list :if={@conversation && @conversation.symptom_report}>
        <:item title="Age">{@referral.patient.age}</:item>
        <:item title="Symptoms">{Enum.join(@conversation.symptom_report.symptoms, ", ")}</:item>
        <:item title="Duration">{@conversation.symptom_report.duration}</:item>
        <:item title="Severity">{@conversation.symptom_report.severity}</:item>
        <:item title="Red flags">{Enum.join(@conversation.symptom_report.red_flags, ", ")}</:item>
      </.list>

      <.link navigate={~p"/clinician"} class="link">&larr; Back to queue</.link>
    </Layouts.app>
    """
  end
end
