defmodule CareRouteWeb.PatientLive.Intake do
  use CareRouteWeb, :live_view

  alias CareRoute.Intake
  alias CareRoute.Intake.Phrases

  # Typical number of patient answers before a recommendation; drives the progress bar.
  @expected_questions 4

  @ai_icon "M12 3a5 5 0 0 0-5 5v3.2c0 .95-.37 1.86-1.04 2.54L5 15h14l-.96-1.26A3.6 3.6 0 0 1 17 11.2V8a5 5 0 0 0-5-5z"
  @patient_icon "M12 12a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9z M4 20.5c0-4 3.6-6.5 8-6.5s8 2.5 8 6.5"

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    conversation = Intake.get_conversation_by_token!(token)
    if connected?(socket), do: Intake.subscribe(conversation.id)

    {:ok,
     socket
     |> assign(page_title: "Symptom intake", lang: conversation.patient.preferred_language)
     |> assign_conversation(conversation)
     |> assign(form: to_form(%{"message" => ""}), sent: 0)}
  end

  @impl true
  # Ignore sends while a reply is pending, so two AI jobs can't race on one conversation.
  def handle_event("send", _params, %{assigns: %{thinking?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("send", %{"message" => message} = params, socket) do
    via = if params["input_mode"] == "voice", do: :voice, else: :text

    case Intake.submit_patient_message(socket.assigns.conversation, message, via: via) do
      {:ok, conversation} ->
        # Bumping `sent` gives the input a new id, so the browser clears it.
        {:noreply, socket |> assign_conversation(conversation) |> update(:sent, &(&1 + 1))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("retry", _params, socket) do
    case Intake.retry_last_answer(socket.assigns.conversation) do
      {:ok, conversation} -> {:noreply, assign_conversation(socket, conversation)}
      {:error, _} -> {:noreply, socket}
    end
  end

  # Reported by the VoiceInput hook when speech recognition fails.
  def handle_event("voice-error", %{"error" => error}, socket) do
    key =
      case error do
        e when e in ["not-allowed", "service-not-allowed", "audio-capture"] -> :voice_blocked
        "no-speech" -> :voice_no_speech
        _ -> :voice_failed
      end

    {:noreply, put_flash(socket, :error, Phrases.t(key, socket.assigns.lang))}
  end

  @impl true
  def handle_info({:conversation_updated, %{id: id}}, socket) do
    {:noreply, assign_conversation(socket, Intake.get_conversation!(id))}
  end

  defp assign_conversation(socket, conversation) do
    last = List.last(conversation.transcript)

    assign(socket,
      conversation: conversation,
      thinking?: conversation.status == :gathering and last["role"] == "patient"
    )
  end

  defp progress(%{status: :urgent}, lang), do: {100, Phrases.t(:progress_urgent, lang)}
  defp progress(%{status: :assessed}, lang), do: {100, Phrases.t(:progress_done, lang)}

  defp progress(%{transcript: transcript}, lang) do
    total = @expected_questions
    answered = Enum.count(transcript, &(&1["role"] == "patient"))
    n = min(answered + 1, total)
    label = Phrases.t(:progress, lang, n: n, total: total)
    label = if n == total, do: label <> " · " <> Phrases.t(:almost_done, lang), else: label
    {min(round(answered / total * 100), 90), label}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :progress, progress(assigns.conversation, assigns.lang))

    ~H"""
    <div class="min-h-screen flex flex-col bg-paper text-ink font-plex antialiased">
      <.emergency_banner lang={@lang} />

      <%!-- Header --%>
      <.patient_header back={~p"/"} back_label={Phrases.t(:back, @lang)}>
        <:actions><.start_over_link label={Phrases.t(:start_over, @lang)} /></:actions>
        <div class="max-w-[340px] mx-auto flex flex-col gap-[5px]">
          <div class="h-[5px] rounded-full bg-line overflow-hidden">
            <div
              id="intake-progress"
              class={[
                "h-full rounded-full transition-[width] duration-500",
                if(@conversation.status == :urgent, do: "bg-[#A23F26]", else: "bg-route")
              ]}
              style={"width: #{elem(@progress, 0)}%"}
            >
            </div>
          </div>
          <div class="text-[11px] text-[#8B958F] text-center">{elem(@progress, 1)}</div>
        </div>
      </.patient_header>

      <%!-- Conversation --%>
      <main class="grow flex justify-center px-4 sm:px-6 pt-8 pb-[190px]">
        <div class="w-full max-w-[620px] flex flex-col gap-[18px]">
          <div id="transcript" phx-hook="ScrollToLatest" class="flex flex-col gap-[18px]">
            <.message
              :for={{msg, i} <- Enum.with_index(@conversation.transcript)}
              id={"msg-#{i}"}
              role={msg["role"]}
              voice={msg["via"] == "voice"}
              voice_label={Phrases.t(:voice_spoken, @lang)}
              notice={Intake.notice?(msg)}
            >
              <span class="whitespace-pre-line">{msg["content"]}</span>
              <div :if={
                Intake.notice?(msg) and @conversation.status == :gathering and
                  i == length(@conversation.transcript) - 1
              }>
                <button
                  id="retry-answer"
                  phx-click="retry"
                  class="mt-3 inline-flex items-center gap-2 bg-route hover:bg-route-dark text-white px-[18px] py-2 rounded-[9px] text-[13.5px] font-semibold"
                >
                  {Phrases.t(:try_again, @lang)}
                </button>
              </div>
              <div :if={
                @conversation.status != :gathering and
                  i == length(@conversation.transcript) - 1 and
                  @conversation.care_recommendation
              }>
                <.link
                  navigate={~p"/intake/#{@conversation.token}/results"}
                  class="mt-3 inline-flex items-center gap-2 bg-route hover:bg-route-dark text-white px-[18px] py-2.5 rounded-[9px] text-[13.5px] font-semibold"
                >
                  {Phrases.t(:see_recommendation, @lang)} <.arrow_icon class="size-3.5" />
                </.link>
              </div>
            </.message>
            <.message :if={@thinking?} id="thinking" role="assistant">
              <span class="flex items-center gap-1 py-1" aria-label="CareRoute is typing">
                <span
                  :for={delay <- ["0ms", "150ms", "300ms"]}
                  class="size-1.5 rounded-full bg-[#8B958F] animate-bounce"
                  style={"animation-delay: #{delay}"}
                ></span>
              </span>
            </.message>
          </div>
        </div>
      </main>

      <%!-- Input bar --%>
      <div class="sticky bottom-0 flex justify-center px-4 sm:px-6 py-[18px] bg-[linear-gradient(180deg,rgba(246,248,246,0)_0%,#F6F8F6_32%)]">
        <.form
          for={@form}
          id="message-form"
          phx-submit="send"
          class="w-full max-w-[620px] flex items-center gap-2.5 bg-white border border-line rounded-[14px] py-2 pr-2 pl-[18px] shadow-[0_6px_22px_rgba(22,32,30,0.06)]"
        >
          <label for={"message-input-#{@sent}"} class="sr-only">{Phrases.t(:message_label, @lang)}</label>
          <input
            id={"message-input-#{@sent}"}
            name="message"
            type="text"
            autocomplete="off"
            value=""
            disabled={@conversation.status != :gathering}
            placeholder={
              if @conversation.status == :gathering,
                do: Phrases.t(:message_placeholder, @lang),
                else: Phrases.t(:closed_placeholder, @lang)
            }
            phx-mounted={@sent > 0 && JS.focus()}
            class="grow min-w-0 border-none outline-none text-sm bg-transparent text-ink placeholder:text-[#A9B3AD] disabled:cursor-not-allowed"
          />
          <%!-- Set to "voice" by the VoiceInput hook; a new id per message resets it. --%>
          <input type="hidden" id={"input-mode-#{@sent}"} name="input_mode" value="text" />
          <div
            :if={@conversation.status == :gathering}
            id="voice-input"
            phx-hook="VoiceInput"
            phx-update="ignore"
            data-lang={speech_lang(@lang)}
            data-label-start={Phrases.t(:voice_start, @lang)}
            data-label-stop={Phrases.t(:voice_stop, @lang)}
            data-label-listening={Phrases.t(:voice_listening, @lang)}
            class="hidden shrink-0"
          >
            <button
              type="button"
              aria-pressed="false"
              aria-label={Phrases.t(:voice_start, @lang)}
              title={Phrases.t(:voice_start, @lang)}
              class="size-[38px] rounded-[10px] border border-line text-route hover:bg-[#EAF1EE] flex items-center justify-center aria-pressed:bg-[#FBEAE6] aria-pressed:border-[#F1CFC5] aria-pressed:text-[#A23F26] aria-pressed:animate-pulse"
            >
              <.mic_icon class="size-[18px]" />
            </button>
          </div>
          <button
            type="submit"
            aria-label={Phrases.t(:send, @lang)}
            disabled={@thinking? or @conversation.status != :gathering}
            class="size-[38px] rounded-[10px] bg-route hover:bg-route-dark disabled:opacity-40 disabled:hover:bg-route flex items-center justify-center shrink-0"
          >
            <.arrow_icon class="size-4 text-white" />
          </button>
        </.form>
      </div>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :role, :string, required: true
  attr :voice, :boolean, default: false
  attr :voice_label, :string, default: nil
  attr :notice, :boolean, default: false
  slot :inner_block, required: true

  defp message(assigns) do
    assigns = assign(assigns, :ai?, assigns.role != "patient")

    ~H"""
    <div id={@id} class={["flex gap-[11px] items-end", !@ai? && "flex-row-reverse"]}>
      <div class={[
        "size-[30px] rounded-full flex items-center justify-center shrink-0",
        if(@ai?, do: "bg-route-soft text-route", else: "bg-[#EDEFEC] text-[#5C665F]")
      ]}>
        <svg
          width="15"
          height="15"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d={if @ai?, do: ai_icon(), else: patient_icon()}></path>
        </svg>
      </div>
      <div class={[
        "max-w-[78%] px-4 py-3 text-sm leading-[1.55]",
        cond do
          @notice ->
            "bg-[#FBF3EA] text-[#6B4E1C] border border-[#F0DCC3] rounded-[4px_16px_16px_16px]"

          @ai? ->
            "bg-white text-ink border border-line rounded-[4px_16px_16px_16px]"

          true ->
            "bg-route text-white rounded-[16px_4px_16px_16px]"
        end
      ]}>
        {render_slot(@inner_block)}
        <span
          :if={@voice}
          class="inline-flex align-middle ml-1.5 opacity-75"
          title={@voice_label}
          aria-label={@voice_label}
        >
          <.mic_icon class="size-3" />
        </span>
      </div>
    </div>
    """
  end

  # Speech recognition locale for the patient's language.
  defp speech_lang("sw"), do: "sw-KE"
  defp speech_lang(_), do: "en-KE"

  attr :class, :string, default: nil

  defp mic_icon(assigns) do
    ~H"""
    <.stroke_icon
      class={@class}
      d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z M5.5 11a6.5 6.5 0 0 0 13 0 M12 17.5V21 M8.5 21h7"
      stroke_width="2"
    />
    """
  end

  defp ai_icon, do: @ai_icon
  defp patient_icon, do: @patient_icon
end
