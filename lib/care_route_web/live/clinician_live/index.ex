defmodule CareRouteWeb.ClinicianLive.Index do
  use CareRouteWeb, :live_view

  alias CareRoute.Referrals

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Referrals.subscribe()

    {:ok,
     socket
     |> assign(page_title: "Referral queue")
     |> stream(:referrals, Referrals.list_referrals())}
  end

  @impl true
  def handle_info({:referral_created, referral}, socket) do
    {:noreply,
     socket
     |> put_flash(
       :info,
       "New referral: #{referral.patient.name || "Patient"} → #{referral.to_facility.name}"
     )
     |> stream_insert(:referrals, referral, at: 0)}
  end

  def handle_info({:referral_updated, referral}, socket) do
    {:noreply, stream_insert(socket, :referrals, referral)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Referral queue
        <:subtitle>New referrals appear here live.</:subtitle>
      </.header>

      <.table
        id="referrals"
        rows={@streams.referrals}
        row_click={fn {_id, r} -> JS.navigate(~p"/clinician/referrals/#{r.id}") end}
      >
        <:col :let={{_id, r}} label="Patient">{r.patient.name || "Anonymous"}</:col>
        <:col :let={{_id, r}} label="To">{r.to_facility.name}</:col>
        <:col :let={{_id, r}} label="Reason">{r.reason}</:col>
        <:col :let={{_id, r}} label="Status">{r.status}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
