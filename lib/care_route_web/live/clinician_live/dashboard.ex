defmodule CareRouteWeb.ClinicianLive.Dashboard do
  @moduledoc """
  Clinician referral queue with a detail panel for the selected referral.

  `/clinician` shows the queue; `/clinician/referrals/:id` also opens one referral.
  `?as=<clinician id>` views the queue as that clinician (their facility only).
  New and updated referrals arrive live over PubSub.
  """
  use CareRouteWeb, :live_view

  alias CareRoute.{Facilities, Referrals}

  @urgency_rank %{urgent: 0, clinic: 1, self_care: 2}
  @tick_ms 30_000

  @icons %{
    search: "M10.5 3a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z M16 16l5.5 5.5"
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Referrals.subscribe()
      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok,
     assign(socket,
       page_title: "Referral queue",
       clinicians: Facilities.list_clinicians(),
       # Only partners can receive a reassigned referral (they use this dashboard).
       facilities: Facilities.list_partners(),
       search: "",
       tab: "all",
       new_ids: MapSet.new(),
       now: DateTime.utc_now()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    viewer = viewer(socket.assigns.clinicians, params["as"])

    socket =
      socket
      |> assign(viewer: viewer)
      |> load_referrals()

    selected =
      case params do
        %{"id" => id} -> Referrals.get_referral!(id)
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(selected: selected)
     |> update(:new_ids, &if(selected, do: MapSet.delete(&1, selected.id), else: &1))}
  end

  defp viewer(_clinicians, nil), do: nil
  defp viewer(clinicians, id), do: Enum.find(clinicians, &(to_string(&1.id) == id))

  defp load_referrals(%{assigns: %{viewer: viewer}} = socket) do
    facility_id = viewer && viewer.facility_id

    assign(socket,
      referrals: Referrals.list_referrals(facility_id: facility_id),
      stats: Referrals.stats(facility_id: facility_id)
    )
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, assign(socket, search: search)}
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(all pending accepted) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_event("set-status", %{"status" => status}, socket)
      when status in ~w(accepted completed) do
    {:ok, _} =
      Referrals.update_referral(socket.assigns.selected, %{
        status: String.to_existing_atom(status)
      })

    {:noreply, socket}
  end

  def handle_event("retry-summary", _params, socket) do
    case Referrals.retry_summary(socket.assigns.selected) do
      {:ok, referral} -> {:noreply, assign(socket, selected: referral)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("regenerate-summary", _params, socket) do
    {:ok, referral} = Referrals.regenerate_summary(socket.assigns.selected)
    {:noreply, assign(socket, selected: referral)}
  end

  def handle_event("reassign", %{"facility_id" => facility_id}, socket) do
    %{selected: selected} = socket.assigns

    if facility_id != "" and facility_id != to_string(selected.to_facility_id) do
      {:ok, referral} = Referrals.reassign_referral(selected, facility_id)
      {:noreply, put_flash(socket, :info, "Reassigned to #{referral.to_facility.name}.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:referral_created, referral}, socket) do
    if visible?(referral, socket.assigns.viewer) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "New referral: #{patient_label(referral)} → #{referral.to_facility.name}"
       )
       |> update(:new_ids, &MapSet.put(&1, referral.id))
       |> load_referrals()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:referral_updated, referral}, socket) do
    socket = load_referrals(socket)

    case socket.assigns.selected do
      %{id: id} when id == referral.id -> {:noreply, assign(socket, selected: referral)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info(:tick, socket), do: {:noreply, assign(socket, now: DateTime.utc_now())}

  defp visible?(_referral, nil), do: true
  defp visible?(referral, viewer), do: referral.to_facility_id == viewer.facility_id

  ## View helpers

  defp shown(referrals, tab, search) do
    term = search |> String.trim() |> String.downcase()

    referrals
    |> Enum.filter(&(tab == "all" or to_string(&1.status) == tab))
    |> Enum.filter(&(term == "" or String.contains?(searchable(&1), term)))
    |> Enum.sort_by(&{Map.get(@urgency_rank, urgency(&1), 3), -DateTime.to_unix(&1.inserted_at)})
  end

  defp searchable(r) do
    [patient_label(r), complaint(r), r.to_facility.name]
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp count(referrals, "all"), do: length(referrals)
  defp count(referrals, status), do: Enum.count(referrals, &(to_string(&1.status) == status))

  defp patient_label(%{patient: %{name: name}}) when name not in [nil, ""], do: name
  defp patient_label(%{patient_id: id}), do: "Patient ##{id}"

  defp urgency(%{conversation: %{care_recommendation: %{urgency_level: level}}}), do: level
  defp urgency(_referral), do: nil

  defp complaint(%{conversation: %{symptom_report: %{} = report}} = r) do
    parts = Enum.take(report.symptoms, 2) ++ List.wrap(report.duration)
    if parts == [], do: r.reason || "", else: parts |> Enum.join(", ") |> String.capitalize()
  end

  defp complaint(r), do: r.reason || ""

  defp level_label(:urgent), do: "Urgent"
  defp level_label(:clinic), do: "Clinic"
  defp level_label(:self_care), do: "Self-care"
  defp level_label(_), do: "Unknown"

  defp level_badge(:urgent), do: "bg-[#FBEAE6] text-[#A23F26]"
  defp level_badge(:clinic), do: "bg-[#FBF3EA] text-[#9A6B1F]"
  defp level_badge(:self_care), do: "bg-route-soft text-route-deep"
  defp level_badge(_), do: "bg-[#EDEFEC] text-[#5C665F]"

  defp status_label(:pending), do: "New"
  defp status_label(:accepted), do: "Accepted"
  defp status_label(:completed), do: "Completed"

  defp status_class(:pending), do: "text-route"
  defp status_class(_), do: "text-[#6B756F]"

  defp ago(datetime, now) do
    case DateTime.diff(now, datetime) do
      s when s < 60 -> "just now"
      s when s < 3600 -> "#{div(s, 60)} min ago"
      s when s < 86_400 -> "#{div(s, 3600)} hr ago"
      s -> "#{div(s, 86_400)} d ago"
    end
  end

  # Pairs each patient answer with the question before it as `{question, answer,
  # spoken?}`; the first answer is the patient's own description.
  defp qa_pairs(%{conversation: %{transcript: transcript}}) do
    transcript
    |> Enum.reject(&CareRoute.Intake.notice?/1)
    |> Enum.reduce({nil, []}, fn
      %{"role" => "patient", "content" => a} = msg, {q, acc} ->
        {nil, [{q, a, msg["via"] == "voice"} | acc]}

      %{"content" => q}, {_q, acc} ->
        {q, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn
      {{_greeting, a, voice?}, 0} -> {"Patient’s description", a, voice?}
      {pair, _i} -> pair
    end)
  end

  defp qa_pairs(_referral), do: []

  defp rationale(%{conversation: %{care_recommendation: %{} = rec}}) do
    reasons = Enum.join(rec.reasoning, " ")
    String.trim("#{reasons} Suggested level: #{level_label(rec.urgency_level)}.")
  end

  defp rationale(_referral), do: nil

  defp initials(nil), do: "All"

  defp initials(%{name: name}) do
    name
    |> String.replace(~r/^(Dr|Nurse)\.?\s+/, "")
    |> String.split()
    |> Enum.map_join(&String.first/1)
    |> String.slice(0, 2)
    |> String.upcase()
  end

  defp query(nil), do: []
  defp query(viewer), do: [as: viewer.id]

  defp referral_path(referral, viewer),
    do: ~p"/clinician/referrals/#{referral.id}?#{query(viewer)}"

  defp icon_path(name), do: Map.fetch!(@icons, name)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :rows, shown(assigns.referrals, assigns.tab, assigns.search))

    ~H"""
    <div class="min-h-screen flex bg-paper text-ink font-plex antialiased">
      <.staff_sidebar active={:referrals} referrals_path={~p"/clinician?#{query(@viewer)}"} />

      <%!-- Main --%>
      <main class="grow min-w-0 flex flex-col">
        <header class="flex flex-wrap items-center justify-between gap-3 px-4 sm:px-8 py-5 border-b border-line bg-white">
          <div class="min-w-0">
            <h1 class="font-display font-semibold text-xl">Referral queue</h1>
            <div id="viewer" class="text-[12.5px] text-[#8B958F] mt-0.5 truncate">
              {if @viewer,
                do: "#{@viewer.name} · #{@viewer.role} · #{@viewer.facility.name}",
                else: "All facilities"}
            </div>
          </div>
          <div class="flex items-center gap-3">
            <form
              id="referral-search-form"
              phx-change="search"
              onsubmit="return false"
              class="relative"
            >
              <.stroke_icon
                class="size-[15px] absolute left-3 top-1/2 -translate-y-1/2 text-[#9CA1A8]"
                d={icon_path(:search)}
                stroke_width="1.8"
              />
              <label for="referral-search" class="sr-only">Search referrals</label>
              <input
                id="referral-search"
                name="search"
                type="search"
                value={@search}
                placeholder="Search referrals"
                phx-debounce="200"
                autocomplete="off"
                class="w-[180px] sm:w-[220px] pl-[34px] pr-3 py-[9px] rounded-[10px] border border-line text-[13px] outline-none focus:border-route"
              />
            </form>
            <details id="viewer-menu" class="relative">
              <summary
                aria-label="View as clinician"
                class="list-none cursor-pointer size-9 rounded-full bg-route-soft flex items-center justify-center text-route text-[13px] font-bold [&::-webkit-details-marker]:hidden"
              >
                {initials(@viewer)}
              </summary>
              <div class="absolute right-0 mt-2 w-64 bg-white border border-line rounded-xl shadow-[0_10px_34px_rgba(22,32,30,0.12)] p-1.5 z-10">
                <div class="px-3 pt-2 pb-1.5 text-[10.5px] font-semibold tracking-[0.05em] uppercase text-[#A9B3AD]">
                  View as
                </div>
                <.link
                  patch={~p"/clinician"}
                  class={[
                    "block px-3 py-2 rounded-lg text-[13px] hover:bg-paper",
                    !@viewer && "bg-route-soft text-route-deep font-semibold"
                  ]}
                >
                  All facilities
                </.link>
                <.link
                  :for={c <- @clinicians}
                  patch={~p"/clinician?as=#{c.id}"}
                  class={[
                    "block px-3 py-2 rounded-lg text-[13px] hover:bg-paper",
                    @viewer && @viewer.id == c.id && "bg-route-soft text-route-deep font-semibold"
                  ]}
                >
                  {c.name}
                  <span class="block text-[11.5px] text-[#8B958F] font-normal">
                    {c.role} · {c.facility && c.facility.name}
                  </span>
                </.link>
              </div>
            </details>
          </div>
        </header>

        <div class="px-4 sm:px-8 pt-6 pb-11 flex flex-col gap-[22px]">
          <%!-- Stats --%>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <.stat id="stat-new-today" label="New referrals today" value={@stats.new_today} />
            <.stat
              id="stat-response"
              label="Avg. response time"
              value={
                if @stats.avg_response_minutes, do: "#{@stats.avg_response_minutes} min", else: "—"
              }
            />
            <.stat id="stat-active" label="Active patients" value={@stats.active_patients} />
          </div>

          <%!-- Queue + detail --%>
          <div class="grid grid-cols-1 xl:grid-cols-[1.5fr_1fr] gap-[18px] items-start">
            <div class="bg-white border border-line rounded-2xl overflow-hidden">
              <div class="flex flex-wrap items-center justify-between gap-2 px-[18px] py-3.5 border-b border-[#EEF1EF]">
                <div class="flex gap-1.5">
                  <button
                    :for={
                      {tab, label} <- [{"all", "All"}, {"pending", "New"}, {"accepted", "Accepted"}]
                    }
                    id={"tab-#{tab}"}
                    phx-click="tab"
                    phx-value-tab={tab}
                    class={[
                      "px-3.5 py-[7px] rounded-full text-[12.5px] font-semibold hover:bg-[#EAF1EE]",
                      if(@tab == tab, do: "bg-route-soft text-route-deep", else: "text-[#6B756F]")
                    ]}
                  >
                    {label} · {count(@referrals, tab)}
                  </button>
                </div>
                <span class="text-xs text-[#8B958F]">Sorted by urgency</span>
              </div>

              <div class="overflow-x-auto">
                <table class="w-full border-collapse">
                  <thead>
                    <tr class="border-b border-[#EEF1EF] text-left">
                      <th
                        :for={
                          {label, pad} <- [
                            {"Patient", "px-[18px]"},
                            {"Level", "px-3"},
                            {"Received", "px-3"},
                            {"Status", "px-[18px]"}
                          ]
                        }
                        class={[
                          pad,
                          "py-2.5 text-[10.5px] font-semibold tracking-[0.05em] uppercase text-[#A9B3AD]"
                        ]}
                      >
                        {label}
                      </th>
                    </tr>
                  </thead>
                  <tbody id="referrals">
                    <tr
                      :for={r <- @rows}
                      id={"referral-#{r.id}"}
                      phx-click={JS.patch(referral_path(r, @viewer))}
                      class={[
                        "border-b border-[#F2F4F2] cursor-pointer",
                        cond do
                          @selected && @selected.id == r.id -> "bg-route-soft"
                          MapSet.member?(@new_ids, r.id) -> "bg-[#F1F8F5] hover:bg-paper"
                          true -> "hover:bg-paper"
                        end
                      ]}
                    >
                      <td class="px-[18px] py-[13px] max-w-[360px]">
                        <div class="flex items-center gap-2 text-[13px] font-semibold">
                          <span
                            :if={MapSet.member?(@new_ids, r.id)}
                            class="size-2 rounded-full bg-route animate-pulse"
                            title="Just arrived"
                          ></span>
                          {patient_label(r)}
                        </div>
                        <div class="text-[11.5px] text-[#8B958F] mt-0.5 truncate">
                          {complaint(r)}<span :if={!@viewer}> · {r.to_facility.name}</span>
                        </div>
                      </td>
                      <td class="px-3 py-[13px]">
                        <span class={[
                          "text-[10.5px] font-semibold px-[9px] py-1 rounded-full whitespace-nowrap",
                          level_badge(urgency(r))
                        ]}>
                          {level_label(urgency(r))}
                        </span>
                      </td>
                      <td class="px-3 py-[13px] text-[12.5px] text-[#6B756F] whitespace-nowrap">
                        {ago(r.inserted_at, @now)}
                      </td>
                      <td class="px-[18px] py-[13px]">
                        <span class={["text-[11.5px] font-semibold", status_class(r.status)]}>
                          {status_label(r.status)}
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
                <p
                  :if={@rows == []}
                  id="empty-queue"
                  class="px-[18px] py-10 text-center text-[13px] text-[#8B958F]"
                >
                  {if @referrals == [],
                    do: "No referrals yet. New ones appear here live.",
                    else: "No referrals match."}
                </p>
              </div>
            </div>

            <.detail
              :if={@selected}
              referral={@selected}
              now={@now}
              facilities={@facilities}
            />
            <div
              :if={!@selected}
              class="hidden xl:block bg-white border border-dashed border-line rounded-2xl p-[22px] text-center text-[13px] text-[#8B958F]"
            >
              Select a referral to see the intake, AI summary and actions.
            </div>
          </div>
        </div>
      </main>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div id={@id} class="bg-white border border-line rounded-[14px] px-5 py-[18px]">
      <div class="text-[11.5px] font-semibold tracking-[0.04em] uppercase text-[#8B958F] mb-2.5">
        {@label}
      </div>
      <div class="font-display text-[25px] font-bold">{@value}</div>
    </div>
    """
  end

  attr :referral, :map, required: true
  attr :now, :any, required: true
  attr :facilities, :list, required: true

  defp detail(assigns) do
    ~H"""
    <section
      id="referral-detail"
      class="bg-white border border-line rounded-2xl p-[22px] xl:sticky xl:top-6"
    >
      <div class="flex items-center justify-between gap-3 mb-3.5">
        <h2 class="text-[15px] font-semibold">{patient_label(@referral)}</h2>
        <span class={[
          "text-[10.5px] font-semibold px-[9px] py-1 rounded-full",
          level_badge(urgency(@referral))
        ]}>
          {level_label(urgency(@referral))}
        </span>
      </div>
      <div class="text-[12.5px] text-[#6B756F] mb-[18px]">
        {complaint(@referral)} · received {ago(@referral.inserted_at, @now)}
        <span class="block mt-0.5">
          Age {@referral.patient.age || "not reported"} ·
          <a
            :if={@referral.patient.contact}
            id="patient-contact"
            href={"tel:" <> String.replace(@referral.patient.contact, ~r/[^+0-9]/, "")}
            class="font-semibold text-route underline underline-offset-2"
          >{@referral.patient.contact}</a><span :if={!@referral.patient.contact}>no phone given</span>
          · to {@referral.to_facility.name} ·
          <span class={["font-semibold", status_class(@referral.status)]}>
            {status_label(@referral.status)}
          </span>
        </span>
      </div>

      <div class="flex items-center justify-between gap-3">
        <.section_label>AI handoff summary</.section_label>
        <button
          :if={@referral.ai_summary}
          id="regenerate-summary"
          phx-click="regenerate-summary"
          class="-mt-2.5 text-[11.5px] font-semibold text-route hover:text-route-dark"
        >
          Regenerate
        </button>
      </div>
      <pre
        :if={@referral.ai_summary}
        id="ai-summary"
        class="whitespace-pre-wrap font-plex text-[12.5px] leading-[1.6] text-ink rounded-xl bg-paper px-3.5 py-3 mb-[18px]"
      >{@referral.ai_summary}</pre>
      <p
        :if={!@referral.ai_summary && !@referral.summary_failed_at}
        class="text-[12.5px] text-[#8B958F] mb-[18px]"
      >
        <span class="loading loading-spinner loading-xs"></span> Generating summary…
      </p>
      <div
        :if={!@referral.ai_summary && @referral.summary_failed_at}
        id="summary-failed"
        class="flex items-center justify-between gap-3 rounded-xl bg-[#FBF3EA] border border-[#F0DCC3] px-3.5 py-3 mb-[18px]"
      >
        <span class="text-[12.5px] text-[#6B4E1C]">
          Summary unavailable — the AI couldn't be reached. The intake below is complete.
        </span>
        <button
          id="retry-summary"
          phx-click="retry-summary"
          class="shrink-0 text-[12.5px] font-semibold text-[#333E37] border border-line bg-white hover:bg-paper px-3 py-1.5 rounded-lg"
        >
          Retry summary
        </button>
      </div>

      <div :if={qa_pairs(@referral) != []}>
        <.section_label>Adaptive intake transcript</.section_label>
        <div class="flex flex-col gap-2.5 mb-[18px]">
          <div :for={{q, a, voice?} <- qa_pairs(@referral)}>
            <div class="text-xs text-[#8B958F]">{q}</div>
            <div class="text-[13px] text-ink font-medium">
              {a}
              <span
                :if={voice?}
                class="ml-1 inline-block align-middle text-[10px] font-semibold uppercase tracking-[0.04em] px-1.5 py-px rounded bg-paper border border-line text-[#6B756F]"
                title="Transcribed from speech; may contain recognition errors"
              >
                spoken
              </span>
            </div>
          </div>
        </div>
      </div>

      <div :if={rationale(@referral)}>
        <.section_label>AI routing rationale</.section_label>
        <p class="text-[12.5px] leading-[1.6] text-ink-muted mb-5">{rationale(@referral)}</p>
      </div>

      <div class="flex flex-col gap-[9px]">
        <button
          :if={@referral.status == :pending}
          id="accept-referral"
          phx-click="set-status"
          phx-value-status="accepted"
          class="bg-route hover:bg-route-dark text-white py-[11px] rounded-[10px] text-[13.5px] font-semibold"
        >
          Accept referral
        </button>
        <button
          :if={@referral.status == :accepted}
          id="complete-referral"
          phx-click="set-status"
          phx-value-status="completed"
          class="bg-route hover:bg-route-dark text-white py-[11px] rounded-[10px] text-[13.5px] font-semibold"
        >
          Mark as completed
        </button>
        <form
          :if={@referral.status != :completed}
          id="reassign-form"
          phx-submit="reassign"
          class="flex gap-2"
        >
          <label for="reassign-facility" class="sr-only">Reassign to facility</label>
          <select
            id="reassign-facility"
            name="facility_id"
            class="grow min-w-0 border border-line rounded-[10px] px-3 py-2.5 text-[13px] bg-white text-[#333E37]"
          >
            <option value="">Reassign to another facility…</option>
            <option :for={f <- @facilities} :if={f.id != @referral.to_facility_id} value={f.id}>
              {f.name}
            </option>
          </select>
          <button class="text-[#333E37] border border-line hover:bg-paper px-4 rounded-[10px] text-[13.5px] font-semibold">
            Reassign
          </button>
        </form>
      </div>
    </section>
    """
  end

  slot :inner_block, required: true

  defp section_label(assigns) do
    ~H"""
    <div class="text-[11px] font-semibold tracking-[0.05em] uppercase text-[#8B958F] mb-2.5">
      {render_slot(@inner_block)}
    </div>
    """
  end
end
