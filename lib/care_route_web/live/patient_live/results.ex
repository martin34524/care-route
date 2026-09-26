defmodule CareRouteWeb.PatientLive.Results do
  @moduledoc """
  The routing result for a finished intake: recommended level of care, nearby
  facilities on a map, and referral requests.
  """
  use CareRouteWeb, :live_view

  alias CareRoute.{Facilities, Intake, Referrals}
  alias CareRoute.Intake.Phrases

  @building_icon "M4 21V7l8-4 8 4v14 M9 21v-6h6v6 M12 7v4 M10 9h4"

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    conversation = Intake.get_conversation_by_token!(token)

    case conversation.care_recommendation do
      nil ->
        # Intake isn't finished yet; send the patient back to the chat.
        {:ok, push_navigate(socket, to: ~p"/intake/#{conversation.token}")}

      rec ->
        origin = Map.put(Facilities.demo_origin(), :source, "demo")

        {:ok,
         assign(socket,
           page_title: "Your recommendation",
           conversation: conversation,
           rec: rec,
           lang: conversation.patient.preferred_language,
           origin: origin,
           facilities: facilities_for(rec.urgency_level, origin),
           referral: Referrals.get_referral_for_conversation(conversation.id)
         )}
    end
  end

  @impl true
  def handle_event("refer", _params, %{assigns: %{referral: %{}}} = socket) do
    {:noreply, socket}
  end

  # "Send referral to a clinician" without a pick goes to the nearest facility.
  def handle_event("refer", params, socket) do
    %{conversation: conversation, facilities: facilities, rec: rec} = socket.assigns

    facility =
      case params do
        %{"facility-id" => id} -> Enum.find(facilities, &(to_string(&1.id) == to_string(id)))
        _ -> List.first(facilities)
      end

    # Only facilities that were actually offered can be chosen.
    if facility do
      {:ok, referral} =
        Referrals.create_referral(%{
          patient_id: conversation.patient_id,
          conversation_id: conversation.id,
          to_facility_id: facility.id,
          reason: "CareRoute recommendation: #{rec.urgency_level}"
        })

      {:noreply,
       socket
       |> assign(referral: referral)
       |> push_event("facility-map:select", %{id: facility.id})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("located", %{"lat" => lat, "lng" => lng}, socket)
      when is_number(lat) and is_number(lng) do
    origin = %{lat: lat, lng: lng, source: "device"}

    case Facilities.with_distances(socket.assigns.facilities, origin) do
      {:ok, facilities} ->
        {:noreply,
         socket
         |> assign(origin: origin, facilities: facilities)
         |> push_event("facility-map:update", %{facilities: map_data(facilities), origin: origin})}

      :out_of_area ->
        {:noreply, put_flash(socket, :info, Phrases.t(:out_of_area, socket.assigns.lang))}
    end
  end

  def handle_event("located", _params, socket), do: {:noreply, socket}

  defp facilities_for(urgency_level, origin) do
    facilities = Facilities.list_facilities_for(urgency_level)

    case Facilities.with_distances(facilities, origin) do
      {:ok, located} -> located
      :out_of_area -> facilities
    end
  end

  defp map_data(facilities) do
    for f <- facilities do
      %{
        id: f.id,
        name: f.name,
        type: f.type,
        address: f.address,
        lat: f.latitude,
        lng: f.longitude,
        distance_km: f.distance_km
      }
    end
  end

  defp map_labels(lang) do
    %{
      go: Phrases.t(:request_referral, lang),
      types: Map.new(~w(clinic hospital specialist)a, &{&1, type_label(&1, lang)})
    }
  end

  defp type_label(type, lang), do: Phrases.t(:"type_#{type}", lang)

  defp directions_url(%{latitude: lat, longitude: lng}) when is_number(lat) and is_number(lng),
    do: "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lng}"

  defp directions_url(_facility), do: nil

  defp urgency_badge(:self_care), do: "bg-route-soft text-route-deep"
  defp urgency_badge(:clinic), do: "bg-[#FBF3EA] text-[#9A6B1F]"
  defp urgency_badge(:urgent), do: "bg-[#FBEAE6] text-[#A23F26]"

  defp facility_badge(%{services: services} = f, lang) do
    if "emergency" in services,
      do: {Phrases.t(:emergency_24_7, lang), "bg-[#FBEAE6] text-[#A23F26]"},
      else: {type_label(f.type, lang), "bg-route-soft text-route-deep"}
  end

  defp services_line(%{services: services}) do
    services |> Enum.map(&String.capitalize/1) |> Enum.join(" · ")
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :building_icon, @building_icon)

    ~H"""
    <div class="min-h-screen bg-paper text-ink font-plex antialiased">
      <.patient_header
        back={~p"/intake/#{@conversation.token}"}
        back_label={Phrases.t(:back_to_chat, @lang)}
      >
        <div class="text-center text-[13.5px] font-semibold text-ink-muted">
          {Phrases.t(:your_recommendation, @lang)}
        </div>
      </.patient_header>

      <main class="max-w-[880px] mx-auto px-4 sm:px-6 pt-8 sm:pt-10 pb-[70px] flex flex-col gap-8">
        <%!-- Recommendation card --%>
        <section
          id="recommendation"
          class="bg-white border border-line rounded-[20px] px-6 py-7 sm:px-[38px] sm:py-9"
        >
          <div class={[
            "inline-flex items-center gap-[7px] px-[13px] py-1.5 rounded-full text-xs font-semibold mb-5",
            urgency_badge(@rec.urgency_level)
          ]}>
            <.warning_icon class="size-3 shrink-0" />
            {Phrases.t(:"urgency_#{@rec.urgency_level}", @lang)}
          </div>

          <div class="text-[13px] font-semibold tracking-[0.04em] uppercase text-[#8B958F] mb-2">
            {Phrases.t(:recommended_level, @lang)}
          </div>
          <h1 class="font-display font-bold text-[32px] sm:text-[38px] leading-tight mb-[18px]">
            {Phrases.t(:"care_#{@rec.urgency_level}", @lang)}
          </h1>

          <p class="text-[14.5px] leading-[1.65] text-ink-muted max-w-[620px] mb-2">
            {Enum.join(@rec.reasoning, " ")} {Phrases.t(:not_a_diagnosis, @lang)}
          </p>
          <div :if={@rec.warning_signs != []} class="flex flex-col gap-1.5 mb-[26px]">
            <div :for={sign <- @rec.warning_signs} class="flex items-start gap-[7px]">
              <.warning_icon class="size-[13px] shrink-0 mt-[3px] text-[#A23F26]" />
              <span class="text-xs leading-[1.5] text-[#A23F26]">{sign}</span>
            </div>
          </div>

          <p
            :if={@referral}
            id="referral-sent"
            class="flex items-start gap-2.5 rounded-[14px] bg-route-soft text-route-deep px-[18px] py-4 text-sm font-medium mb-5"
          >
            <.check_icon class="size-4 shrink-0 mt-0.5" />
            {Phrases.t(:referral_sent, @lang, facility: @referral.to_facility.name)}
          </p>

          <div class="flex flex-wrap items-center gap-3.5">
            <a
              href="#facilities"
              class="bg-route hover:bg-route-dark text-white px-[22px] py-3 rounded-[10px] text-sm font-semibold inline-flex items-center gap-2"
            >
              {Phrases.t(:"find_#{@rec.urgency_level}", @lang)}
              <.arrow_icon class="size-[15px]" />
            </a>
            <button
              :if={!@referral && @facilities != []}
              id="send-referral"
              phx-click="refer"
              class="text-[#333E37] px-5 py-3 rounded-[10px] text-sm font-semibold border border-line hover:bg-[#EAF1EE]"
            >
              {Phrases.t(:send_referral, @lang)}
            </button>
          </div>
        </section>

        <%!-- Facilities --%>
        <section id="facilities" class="scroll-mt-6">
          <div class="flex items-baseline justify-between gap-3 mb-4">
            <h2 class="text-base font-semibold">{Phrases.t(:facilities_near, @lang)}</h2>
            <div class="text-[12.5px] text-[#8B958F]">{Phrases.t(:sorted_by_distance, @lang)}</div>
          </div>

          <div
            :if={@facilities != []}
            id="facility-map"
            phx-hook="FacilityMap"
            phx-update="ignore"
            data-facilities={Jason.encode!(map_data(@facilities))}
            data-origin={Jason.encode!(@origin)}
            data-labels={Jason.encode!(map_labels(@lang))}
            class="mb-3.5"
          >
            <div data-map class="h-64 sm:h-80 rounded-2xl border border-line z-0"></div>
          </div>

          <div class="flex flex-col gap-3.5">
            <div
              :for={{f, i} <- Enum.with_index(@facilities, 1)}
              id={"facility-#{f.id}"}
              class={[
                "bg-white border rounded-2xl px-5 py-5 sm:px-6 sm:py-[22px] flex flex-col sm:flex-row sm:items-center justify-between gap-4 sm:gap-5 transition-[box-shadow,border-color] duration-150 hover:border-[#CFDAD5] hover:shadow-[0_3px_14px_rgba(22,32,30,0.06)]",
                if(@referral && @referral.to_facility_id == f.id,
                  do: "border-route",
                  else: "border-line"
                )
              ]}
            >
              <div class="flex gap-4 items-start min-w-0">
                <div class="relative size-[42px] rounded-[11px] bg-route-soft flex items-center justify-center text-route shrink-0">
                  <.stroke_icon class="size-5" d={@building_icon} stroke_width="1.7" />
                  <span class={[
                    "map-pin map-pin-#{f.type} absolute -top-2 -left-2 !size-5 !text-[10px] !border"
                  ]}>
                    {i}
                  </span>
                </div>
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-x-2.5 gap-y-1 mb-1">
                    <span class="text-[15px] font-semibold">{f.name}</span>
                    <% {badge, badge_class} = facility_badge(f, @lang) %>
                    <span class={[
                      "text-[10.5px] font-semibold px-[9px] py-[3px] rounded-full",
                      badge_class
                    ]}>
                      {badge}
                    </span>
                  </div>
                  <div class="text-[12.5px] text-[#6B756F] mb-0.5">
                    {[f.address, f.distance_km && "#{f.distance_km} km"]
                    |> Enum.reject(&is_nil/1)
                    |> Enum.join(" · ")}
                  </div>
                  <div :if={f.services != []} class="text-[12.5px] text-[#8B958F]">
                    {services_line(f)}
                  </div>
                </div>
              </div>
              <div class="flex gap-2.5 shrink-0">
                <a
                  :if={directions_url(f)}
                  href={directions_url(f)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-[13px] font-semibold text-[#333E37] px-[15px] py-[9px] rounded-[9px] border border-line hover:bg-[#EAF1EE]"
                >
                  {Phrases.t(:directions, @lang)}
                </a>
                <button
                  :if={!@referral}
                  phx-click="refer"
                  phx-value-facility-id={f.id}
                  class="text-[13px] font-semibold text-white bg-route hover:bg-route-dark px-[15px] py-[9px] rounded-[9px]"
                >
                  {Phrases.t(:request_referral, @lang)}
                </button>
                <span
                  :if={@referral && @referral.to_facility_id == f.id}
                  class="inline-flex items-center gap-1.5 text-[13px] font-semibold text-route-deep bg-route-soft px-[15px] py-[9px] rounded-[9px]"
                >
                  <.check_icon class="size-3.5" /> {Phrases.t(:referral_sent_short, @lang)}
                </span>
              </div>
            </div>
          </div>
        </section>

        <%!-- Disclaimer --%>
        <div class="flex gap-3 px-5 py-4 rounded-[14px] bg-[#FBF3EA] border border-[#F0DCC3]">
          <.shield_icon class="size-[17px] shrink-0 mt-px text-[#9A6B1F]" />
          <div class="text-[12.5px] leading-[1.6] text-[#6B4E1C]">
            {Phrases.t(:disclaimer, @lang)}
          </div>
        </div>
      </main>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
