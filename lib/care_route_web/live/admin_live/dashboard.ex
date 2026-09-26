defmodule CareRouteWeb.AdminLive.Dashboard do
  use CareRouteWeb, :live_view

  alias CareRoute.{Intake, Referrals, Routing}

  # Conversations aren't broadcast network-wide, so poll for those counts.
  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Referrals.subscribe()
      :timer.send_interval(@refresh_ms, :refresh)
    end

    {:ok, socket |> assign(page_title: "Network overview") |> load_stats()}
  end

  @impl true
  def handle_info(_event, socket), do: {:noreply, load_stats(socket)}

  defp load_stats(socket) do
    assign(socket,
      by_status: Intake.count_conversations_by_status(),
      by_urgency: Routing.count_by_urgency(),
      facilities: Referrals.load_by_facility(),
      recent: Referrals.list_referrals() |> Enum.take(5)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Network overview
        <:subtitle>Live view of patient routing across facilities.</:subtitle>
      </.header>

      <div class="stats stats-vertical sm:stats-horizontal w-full shadow-sm">
        <.stat id="stat-in-progress" title="In intake" value={Map.get(@by_status, :gathering, 0)} />
        <.stat id="stat-self-care" title="Self-care" value={Map.get(@by_urgency, :self_care, 0)} />
        <.stat id="stat-clinic" title="Clinic" value={Map.get(@by_urgency, :clinic, 0)} />
        <.stat
          id="stat-urgent"
          title="Urgent"
          value={Map.get(@by_urgency, :urgent, 0)}
          class="text-error"
        />
      </div>

      <h3 class="font-semibold pt-4">Facility load</h3>
      <.table id="facility-load" rows={@facilities}>
        <:col :let={f} label="Facility">{f.facility}</:col>
        <:col :let={f} label="Type">{f.type}</:col>
        <:col :let={f} label="Pending">{f.pending}</:col>
        <:col :let={f} label="Total referrals">{f.total}</:col>
      </.table>

      <h3 class="font-semibold pt-4">Recent referrals</h3>
      <.table id="recent-referrals" rows={@recent}>
        <:col :let={r} label="Patient">{r.patient.name || "Anonymous"}</:col>
        <:col :let={r} label="To">{r.to_facility.name}</:col>
        <:col :let={r} label="Status">{r.status}</:col>
      </.table>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :class, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div id={@id} class="stat">
      <div class="stat-title">{@title}</div>
      <div class={["stat-value", @class]}>{@value}</div>
    </div>
    """
  end
end
