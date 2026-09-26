defmodule CareRouteWeb.AdminLive.Dashboard do
  @moduledoc """
  Network overview: live routing counts, the split of recommendations by level
  of care, and referral load per facility. Updates on every conversation and
  referral change (PubSub), with no polling.
  """
  use CareRouteWeb, :live_view

  alias CareRoute.{Intake, Referrals, Routing}

  # Status colours for levels of care, checked with the dataviz palette
  # validator (lightness, chroma, colour-blind separation, contrast).
  @levels [
    {:self_care, "Self-care", "#23906F"},
    {:clinic, "Clinic", "#B67B1F"},
    {:urgent, "Urgent", "#A23F26"}
  ]
  @waiting_color "#B67B1F"
  @handled_color "#23906F"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Referrals.subscribe()
      Intake.subscribe_network()
    end

    {:ok, socket |> assign(page_title: "Network overview") |> load_stats()}
  end

  @impl true
  def handle_info(_change, socket), do: {:noreply, load_stats(socket)}

  defp load_stats(socket) do
    by_urgency = Routing.count_by_urgency()

    assign(socket,
      by_status: Intake.count_conversations_by_status(),
      by_urgency: by_urgency,
      levels: level_rows(by_urgency),
      facilities: Referrals.load_by_facility(),
      stats: Referrals.stats(),
      recent: Referrals.list_referrals() |> Enum.take(5)
    )
  end

  defp level_rows(by_urgency) do
    total = by_urgency |> Map.values() |> Enum.sum()

    for {level, label, color} <- @levels do
      count = Map.get(by_urgency, level, 0)
      pct = if total > 0, do: round(count * 100 / total), else: 0

      %{
        level: level,
        label: label,
        color: color,
        count: count,
        pct: pct,
        share: share(count, total)
      }
    end
  end

  defp share(_count, 0), do: 0
  defp share(count, total), do: count / total * 100

  defp waiting_total(facilities), do: facilities |> Enum.map(& &1.pending) |> Enum.sum()

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        waiting_color: @waiting_color,
        handled_color: @handled_color,
        max_load: assigns.facilities |> Enum.map(& &1.total) |> Enum.max(fn -> 0 end) |> max(1),
        level_total: Enum.sum(Enum.map(assigns.levels, & &1.count))
      )

    ~H"""
    <div class="min-h-screen flex bg-paper text-ink font-plex antialiased">
      <.staff_sidebar active={:network} />

      <main class="grow min-w-0 flex flex-col">
        <header class="px-4 sm:px-8 py-5 border-b border-line bg-white">
          <h1 class="font-display font-semibold text-xl">Network overview</h1>
          <div class="text-[12.5px] text-[#8B958F] mt-0.5">
            Live view of patient routing across facilities
          </div>
        </header>

        <div class="px-4 sm:px-8 pt-6 pb-11 flex flex-col gap-[22px]">
          <div class="grid grid-cols-2 xl:grid-cols-4 gap-4">
            <.stat
              id="stat-in-progress"
              label="In intake now"
              value={Map.get(@by_status, :gathering, 0)}
            />
            <.stat id="stat-referrals-today" label="Referrals today" value={@stats.new_today} />
            <.stat
              id="stat-waiting"
              label="Waiting for a clinician"
              value={waiting_total(@facilities)}
            />
            <.stat
              id="stat-response"
              label="Avg. response time"
              value={
                if @stats.avg_response_minutes, do: "#{@stats.avg_response_minutes} min", else: "—"
              }
            />
          </div>

          <div class="grid grid-cols-1 xl:grid-cols-2 gap-[18px] items-start">
            <%!-- Recommendations by level of care: one part-to-whole bar --%>
            <section id="levels-chart" class="bg-white border border-line rounded-2xl p-[22px]">
              <h2 class="text-[15px] font-semibold">Recommendations by level of care</h2>
              <p class="text-[12.5px] text-[#8B958F] mt-0.5 mb-5">
                {@level_total} recommendations so far
              </p>

              <div
                :if={@level_total > 0}
                role="img"
                aria-label={Enum.map_join(@levels, ", ", &"#{&1.label}: #{&1.count} (#{&1.pct}%)")}
                class="flex h-7 gap-[2px] rounded overflow-hidden"
              >
                <div
                  :for={l <- @levels}
                  :if={l.count > 0}
                  title={"#{l.label}: #{l.count} (#{l.pct}%)"}
                  class="h-full first:rounded-l last:rounded-r hover:opacity-85"
                  style={"width: #{l.share}%; background: #{l.color}"}
                >
                </div>
              </div>
              <p :if={@level_total == 0} class="text-[13px] text-[#8B958F]">
                No recommendations yet.
              </p>

              <ul class="mt-4 flex flex-col gap-2">
                <li
                  :for={l <- @levels}
                  id={"level-#{l.level}"}
                  class="flex items-center gap-2.5 text-[13px]"
                >
                  <span class="size-3 rounded-sm shrink-0" style={"background: #{l.color}"}></span>
                  <span class="grow text-[#333E37]">{l.label}</span>
                  <span class="font-semibold tabular-nums">{l.count}</span>
                  <span class="w-10 text-right text-[#8B958F] tabular-nums">{l.pct}%</span>
                </li>
              </ul>
            </section>

            <%!-- Referral load per facility: waiting + handled bars, one scale --%>
            <section id="load-chart" class="bg-white border border-line rounded-2xl p-[22px]">
              <div class="flex flex-wrap items-baseline justify-between gap-2 mb-5">
                <div>
                  <h2 class="text-[15px] font-semibold">Referral load by facility</h2>
                  <p class="text-[12.5px] text-[#8B958F] mt-0.5">All referrals received</p>
                </div>
                <div class="flex items-center gap-3.5 text-[12px] text-[#6B756F]">
                  <span class="flex items-center gap-1.5">
                    <span class="size-2.5 rounded-sm" style={"background: #{@waiting_color}"}></span>
                    Waiting
                  </span>
                  <span class="flex items-center gap-1.5">
                    <span class="size-2.5 rounded-sm" style={"background: #{@handled_color}"}></span>
                    Handled
                  </span>
                </div>
              </div>

              <div class="flex flex-col gap-3.5">
                <div :for={f <- @facilities} id={"load-#{f.id}"}>
                  <div class="flex items-baseline justify-between gap-3 mb-1.5">
                    <span class="text-[13px] font-medium truncate">{f.facility}</span>
                    <span class="text-[12px] text-[#6B756F] tabular-nums shrink-0">
                      {f.total} total<span :if={f.pending > 0}> · {f.pending} waiting</span>
                    </span>
                  </div>
                  <div class="h-3.5 rounded bg-paper">
                    <div
                      :if={f.total > 0}
                      class="flex h-full gap-[2px]"
                      style={"width: #{f.total / @max_load * 100}%"}
                    >
                      <div
                        :if={f.pending > 0}
                        title={"#{f.facility}: #{f.pending} waiting"}
                        class="h-full first:rounded-l last:rounded-r hover:opacity-85"
                        style={"width: #{f.pending / f.total * 100}%; background: #{@waiting_color}"}
                      >
                      </div>
                      <div
                        :if={f.total - f.pending > 0}
                        title={"#{f.facility}: #{f.total - f.pending} handled"}
                        class="h-full first:rounded-l last:rounded-r hover:opacity-85"
                        style={"width: #{(f.total - f.pending) / f.total * 100}%; background: #{@handled_color}"}
                      >
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </section>
          </div>

          <section class="bg-white border border-line rounded-2xl overflow-hidden">
            <h2 class="text-[15px] font-semibold px-[22px] py-4 border-b border-[#EEF1EF]">
              Recent referrals
            </h2>
            <.link
              :for={r <- @recent}
              navigate={~p"/clinician/referrals/#{r.id}"}
              class="flex items-center justify-between gap-3 px-[22px] py-3 border-b border-[#F2F4F2] last:border-b-0 hover:bg-paper"
            >
              <div class="min-w-0">
                <div class="text-[13px] font-semibold">
                  {r.patient.name || "Patient ##{r.patient_id}"}
                </div>
                <div class="text-[11.5px] text-[#8B958F] truncate">→ {r.to_facility.name}</div>
              </div>
              <span class="text-[11.5px] font-semibold text-[#6B756F] capitalize">{r.status}</span>
            </.link>
            <p :if={@recent == []} class="px-[22px] py-6 text-[13px] text-[#8B958F]">
              No referrals yet.
            </p>
          </section>
        </div>
      </main>
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
end
