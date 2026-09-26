defmodule CareRouteWeb.PatientLive.Start do
  @moduledoc """
  First patient screen: language, a couple of details, and consent, then a new
  conversation. The page switches language as soon as one is picked.
  """
  use CareRouteWeb, :live_view

  alias CareRoute.Intake
  alias CareRoute.Intake.Phrases

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Get care guidance",
       lang: "en",
       params: %{"name" => "", "age" => "", "contact" => "", "consent" => "false"},
       error: nil
     )}
  end

  @impl true
  def handle_event("change", %{"patient" => params}, socket) do
    {:noreply, assign(socket, params: params, lang: language(params, socket), error: nil)}
  end

  def handle_event("start", %{"patient" => params}, socket) do
    lang = language(params, socket)
    socket = assign(socket, params: params, lang: lang)

    if params["consent"] == "true" do
      attrs = %{
        name: blank_to_nil(params["name"]),
        age: blank_to_nil(params["age"]),
        contact: blank_to_nil(params["contact"]),
        preferred_language: lang,
        consented_at: DateTime.utc_now(:second)
      }

      with {:ok, patient} <- Intake.create_patient(attrs),
           {:ok, conversation} <- Intake.start_conversation(patient) do
        {:noreply, push_navigate(socket, to: ~p"/intake/#{conversation.token}")}
      else
        {:error, %Ecto.Changeset{errors: errors}} ->
          key =
            cond do
              Keyword.has_key?(errors, :age) -> :age_invalid
              Keyword.has_key?(errors, :contact) -> :phone_invalid
              true -> :consent_required
            end

          {:noreply, assign(socket, error: key)}
      end
    else
      {:noreply, assign(socket, error: :consent_required)}
    end
  end

  defp language(%{"preferred_language" => lang}, _socket)
       when is_map_key(%{"en" => 1, "sw" => 1}, lang),
       do: lang

  defp language(_params, socket), do: socket.assigns.lang

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: String.trim(value)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-paper text-ink font-plex antialiased">
      <.emergency_banner lang={@lang} />
      <.patient_header back={~p"/"} back_label={Phrases.t(:back, @lang)}>
        <div class="text-center text-[13.5px] font-semibold text-ink-muted">
          {Phrases.t(:start_title, @lang)}
        </div>
      </.patient_header>

      <main class="max-w-[520px] mx-auto px-4 sm:px-6 pt-8 sm:pt-10 pb-16">
        <section class="bg-white border border-line rounded-[20px] px-6 py-7 sm:px-8 sm:py-8">
          <div class="inline-flex items-center gap-[7px] px-[13px] py-1.5 rounded-full bg-route-soft text-route-deep text-xs font-semibold mb-4">
            <.shield_icon class="size-3 shrink-0" /> CareRoute AI
          </div>
          <h1 class="font-display font-semibold text-[28px] sm:text-[30px] leading-tight mb-2">
            {Phrases.t(:start_title, @lang)}
          </h1>
          <p class="text-[14.5px] leading-[1.6] text-ink-muted mb-7">
            {Phrases.t(:start_subtitle, @lang)}
          </p>

          <form id="start-form" phx-change="change" phx-submit="start" class="flex flex-col gap-5">
            <fieldset>
              <legend class="text-[13px] font-semibold mb-2">
                {Phrases.t(:field_language, @lang)}
              </legend>
              <div class="grid grid-cols-2 gap-2.5">
                <label
                  :for={{code, name} <- Phrases.languages()}
                  class={[
                    "flex items-center justify-center gap-2 rounded-[10px] border px-4 py-2.5 text-sm font-semibold cursor-pointer",
                    if(@lang == code,
                      do: "border-route bg-route-soft text-route-deep",
                      else: "border-line text-ink-muted hover:bg-paper"
                    )
                  ]}
                >
                  <input
                    type="radio"
                    name="patient[preferred_language]"
                    value={code}
                    checked={@lang == code}
                    class="sr-only"
                  />
                  {name}
                </label>
              </div>
            </fieldset>

            <div>
              <label for="patient-name" class="block text-[13px] font-semibold mb-1.5">
                {Phrases.t(:field_name, @lang)}
              </label>
              <input
                id="patient-name"
                name="patient[name]"
                type="text"
                maxlength="80"
                autocomplete="given-name"
                value={@params["name"]}
                class="w-full rounded-[10px] border border-line px-3.5 py-2.5 text-sm outline-none focus:border-route"
              />
            </div>

            <div>
              <label for="patient-age" class="block text-[13px] font-semibold mb-1.5">
                {Phrases.t(:field_age, @lang)}
              </label>
              <input
                id="patient-age"
                name="patient[age]"
                type="number"
                inputmode="numeric"
                min="0"
                max="129"
                value={@params["age"]}
                class={[
                  "w-full rounded-[10px] border px-3.5 py-2.5 text-sm outline-none focus:border-route",
                  if(@error == :age_invalid, do: "border-[#A23F26]", else: "border-line")
                ]}
              />
            </div>

            <div>
              <label for="patient-contact" class="block text-[13px] font-semibold mb-1.5">
                {Phrases.t(:field_phone, @lang)}
              </label>
              <input
                id="patient-contact"
                name="patient[contact]"
                type="tel"
                autocomplete="tel"
                maxlength="20"
                value={@params["contact"]}
                class={[
                  "w-full rounded-[10px] border px-3.5 py-2.5 text-sm outline-none focus:border-route",
                  if(@error == :phone_invalid, do: "border-[#A23F26]", else: "border-line")
                ]}
              />
            </div>

            <div class="rounded-[14px] bg-paper border border-line px-4 py-3.5">
              <label class="flex items-start gap-3 cursor-pointer">
                <input type="hidden" name="patient[consent]" value="false" />
                <input
                  id="patient-consent"
                  type="checkbox"
                  name="patient[consent]"
                  value="true"
                  checked={@params["consent"] == "true"}
                  class="mt-0.5 size-4 shrink-0 accent-[#1D6B64]"
                />
                <span class="text-[13px] leading-[1.55] text-[#333E37]">
                  {Phrases.t(:consent, @lang)}
                </span>
              </label>
              <.link
                href={~p"/privacy"}
                target="_blank"
                class="inline-block mt-2 ml-7 text-[12.5px] font-semibold text-route underline underline-offset-2"
              >
                {Phrases.t(:privacy_link, @lang)}
              </.link>
            </div>

            <p :if={@error} id="start-error" role="alert" class="text-[13px] text-[#A23F26]">
              {Phrases.t(@error, @lang)}
            </p>

            <button
              type="submit"
              disabled={@params["consent"] != "true"}
              class="w-full bg-route hover:bg-route-dark disabled:opacity-40 disabled:hover:bg-route text-white py-3 rounded-[10px] text-[15px] font-semibold inline-flex items-center justify-center gap-2"
            >
              {Phrases.t(:start, @lang)} <.arrow_icon class="size-4" />
            </button>
          </form>
        </section>
      </main>
    </div>
    """
  end
end
