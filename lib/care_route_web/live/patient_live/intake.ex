defmodule CareRouteWeb.PatientLive.Intake do
  use CareRouteWeb, :live_view

  alias CareRoute.{Facilities, Intake, Referrals}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    conversation = Intake.get_conversation!(id)
    if connected?(socket), do: Intake.subscribe(conversation.id)

    {:ok,
     socket
     |> assign(page_title: "CareRoute", referral: nil)
     |> assign_conversation(conversation)
     |> assign(form: to_form(%{"message" => ""}))}
  end

  @impl true
  def handle_event("send", %{"message" => message}, socket) do
    case Intake.submit_patient_message(socket.assigns.conversation, message) do
      {:ok, conversation} ->
        {:noreply,
         socket |> assign_conversation(conversation) |> assign(form: to_form(%{"message" => ""}))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("refer", %{"facility-id" => facility_id}, socket) do
    %{conversation: conversation} = socket.assigns

    {:ok, referral} =
      Referrals.create_referral(%{
        patient_id: conversation.patient_id,
        conversation_id: conversation.id,
        to_facility_id: facility_id,
        reason: "CareRoute recommendation: #{conversation.care_recommendation.urgency_level}"
      })

    {:noreply, assign(socket, referral: referral)}
  end

  @impl true
  def handle_info({:conversation_updated, %{id: id}}, socket) do
    {:noreply, assign_conversation(socket, Intake.get_conversation!(id))}
  end

  defp assign_conversation(socket, conversation) do
    rec = conversation.care_recommendation
    last = List.last(conversation.transcript)

    assign(socket,
      conversation: conversation,
      thinking?: conversation.status == :gathering and last["role"] == "patient",
      facilities: if(rec, do: Facilities.list_facilities_for(rec.urgency_level), else: [])
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="transcript" class="space-y-3">
        <div
          :for={{msg, i} <- Enum.with_index(@conversation.transcript)}
          id={"msg-#{i}"}
          class={["chat", if(msg["role"] == "patient", do: "chat-end", else: "chat-start")]}
        >
          <div class={[
            "chat-bubble",
            msg["role"] == "patient" && "chat-bubble-primary"
          ]}>
            {msg["content"]}
          </div>
        </div>
        <div :if={@thinking?} class="chat chat-start">
          <div class="chat-bubble"><span class="loading loading-dots loading-sm"></span></div>
        </div>
      </div>

      <.form
        :if={@conversation.status == :gathering}
        for={@form}
        id="message-form"
        phx-submit="send"
        class="flex gap-2 items-start"
      >
        <div class="flex-1">
          <.input field={@form[:message]} placeholder="Type your answer…" autocomplete="off" />
        </div>
        <.button variant="primary" disabled={@thinking?}>Send</.button>
      </.form>

      <.recommendation
        :if={@conversation.care_recommendation}
        rec={@conversation.care_recommendation}
        facilities={@facilities}
        referral={@referral}
      />
    </Layouts.app>
    """
  end

  attr :rec, :map, required: true
  attr :facilities, :list, required: true
  attr :referral, :map

  defp recommendation(assigns) do
    ~H"""
    <div id="recommendation" class={["card border-2", level_class(@rec.urgency_level)]}>
      <div class="card-body">
        <h2 class="card-title">{level_title(@rec.urgency_level)}</h2>
        <ul :if={@rec.reasoning != []} class="list-disc pl-5">
          <li :for={r <- @rec.reasoning}>{r}</li>
        </ul>
        <div :if={@rec.warning_signs != []}>
          <p class="font-semibold mt-2">Get urgent help if you notice:</p>
          <ul class="list-disc pl-5">
            <li :for={w <- @rec.warning_signs}>{w}</li>
          </ul>
        </div>
      </div>
    </div>

    <div :if={@rec.urgency_level != :self_care} id="facilities" class="space-y-2">
      <p :if={@referral} class="alert alert-success">
        Referral sent to {@referral.to_facility.name}. They'll have your details when you arrive.
      </p>
      <h3 :if={!@referral} class="font-semibold">Nearby places that can help</h3>
      <div
        :for={f <- @facilities}
        :if={!@referral}
        id={"facility-#{f.id}"}
        class="flex items-center justify-between rounded-box border border-base-300 p-3"
      >
        <div>
          <p class="font-medium">{f.name}</p>
          <p class="text-sm opacity-70">{f.type} · {f.distance_km} km</p>
        </div>
        <.button phx-click="refer" phx-value-facility-id={f.id}>Go here</.button>
      </div>
    </div>
    """
  end

  defp level_title(:self_care), do: "You can likely care for this at home"
  defp level_title(:clinic), do: "Visit a clinic"
  defp level_title(:urgent), do: "Seek urgent care now"

  defp level_class(:self_care), do: "border-success"
  defp level_class(:clinic), do: "border-warning"
  defp level_class(:urgent), do: "border-error"
end
