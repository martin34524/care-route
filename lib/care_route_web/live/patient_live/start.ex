defmodule CareRouteWeb.PatientLive.Start do
  use CareRouteWeb, :live_view

  alias CareRoute.Intake

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"name" => "", "age" => "", "preferred_language" => "en"})
    {:ok, assign(socket, page_title: "Get care guidance", form: form)}
  end

  @impl true
  def handle_event("start", params, socket) do
    with {:ok, patient} <- Intake.create_patient(params),
         {:ok, conversation} <- Intake.start_conversation(patient) do
      {:noreply, push_navigate(socket, to: ~p"/intake/#{conversation.id}")}
    else
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Not sure where to go for care?
        <:subtitle>
          Describe what's happening and CareRoute will suggest a next step: self-care,
          a clinic visit, or urgent care. CareRoute does not diagnose.
        </:subtitle>
      </.header>

      <.form for={@form} id="start-form" phx-submit="start" class="space-y-2">
        <.input field={@form[:name]} label="Name (optional)" />
        <.input field={@form[:age]} type="number" label="Age of the person needing care" />
        <.input
          field={@form[:preferred_language]}
          type="select"
          label="Language"
          options={[{"English", "en"}, {"Kiswahili", "sw"}]}
        />
        <.button variant="primary" class="w-full">Start</.button>
      </.form>
    </Layouts.app>
    """
  end
end
