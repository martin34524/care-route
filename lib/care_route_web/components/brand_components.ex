defmodule CareRouteWeb.BrandComponents do
  @moduledoc """
  Shared pieces of the CareRoute brand design: icons and the patient page header.
  """
  use Phoenix.Component

  @doc "A 24x24 stroke icon; pass the SVG path data as `d`."
  attr :d, :string, required: true
  attr :class, :string, default: nil
  attr :stroke_width, :string, default: "2"

  def stroke_icon(assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width={@stroke_width}
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d={@d}></path>
    </svg>
    """
  end

  attr :class, :string, default: nil

  def logo_icon(assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <circle cx="6" cy="18" r="2.2"></circle>
      <circle cx="18" cy="6" r="2.2"></circle>
      <path d="M8.1 16.5 15 8.7" stroke-dasharray="2 3"></path>
    </svg>
    """
  end

  attr :class, :string, default: nil

  def arrow_icon(assigns) do
    ~H"""
    <.stroke_icon class={@class} d="M5 12h14M13 6l6 6-6 6" stroke_width="2.1" />
    """
  end

  attr :class, :string, default: nil

  def check_icon(assigns) do
    ~H"""
    <.stroke_icon class={@class} d="M5 12l4 4 10-10" stroke_width="2.3" />
    """
  end

  attr :class, :string, default: nil

  def warning_icon(assigns) do
    ~H"""
    <.stroke_icon class={@class} d="M12 3 22 20H2z M12 9.3v4.7 M12 17h.01" stroke_width="2.2" />
    """
  end

  attr :class, :string, default: nil

  def shield_icon(assigns) do
    ~H"""
    <.stroke_icon
      class={@class}
      d="M12 3 4 6.5v5c0 5 3.4 8.9 8 10 4.6-1.1 8-5 8-10v-5z M12 8v5 M12 16h.01"
      stroke_width="1.9"
    />
    """
  end

  @doc "Tap-to-call link for the first configured emergency number."
  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :class, :string, default: nil

  def call_link(assigns) do
    assigns = assign(assigns, :number, CareRoute.Intake.Phrases.emergency_number())

    ~H"""
    <a id={@id} href={"tel:#{@number}"} class={["inline-flex items-center gap-1.5", @class]}>
      <.stroke_icon
        class="size-[15px] shrink-0"
        d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"
        stroke_width="2"
      />
      {@label}
    </a>
    """
  end

  @doc "Red strip with the emergency advice and a tap-to-call link."
  attr :lang, :string, required: true

  def emergency_banner(assigns) do
    ~H"""
    <div
      role="note"
      class="flex items-center justify-center gap-[9px] px-5 py-2.5 bg-[#FBEAE6] border-b border-[#F1CFC5]"
    >
      <.warning_icon class="size-[15px] shrink-0 text-[#A23F26]" />
      <span class="text-[12.5px] text-[#7A2E1B]">
        {CareRoute.Intake.Phrases.t(:emergency_banner, @lang)}
      </span>
      <.call_link
        id="emergency-call"
        label={
          CareRoute.Intake.Phrases.t(:call_now, @lang,
            number: CareRoute.Intake.Phrases.emergency_number()
          )
        }
        class="shrink-0 text-[12px] font-semibold text-white bg-[#A23F26] hover:bg-[#8A3420] px-2.5 py-1 rounded-md"
      />
    </div>
    """
  end

  @doc "Left navigation shared by the clinician and admin pages (hidden on small screens)."
  attr :active, :atom, required: true, values: [:referrals, :network]
  attr :referrals_path, :string, default: "/clinician"

  def staff_sidebar(assigns) do
    ~H"""
    <nav
      aria-label="Staff navigation"
      class="hidden lg:flex sticky top-0 h-screen w-[232px] shrink-0 bg-white border-r border-line px-3.5 py-5 flex-col gap-[3px]"
    >
      <div class="flex items-center gap-2 px-2.5 pt-1.5 pb-[22px]">
        <.logo_icon class="size-[22px] text-route" />
        <span class="font-display font-semibold text-[15px]">CareRoute</span>
      </div>
      <.link navigate={@referrals_path} class={side_link(@active == :referrals)}>
        <.stroke_icon class="size-[17px]" d="M4 4.5h16V16H9l-5 4.5z" stroke_width="1.8" /> Referrals
      </.link>
      <.link navigate="/admin" class={side_link(@active == :network)}>
        <.stroke_icon class="size-[17px]" d="M4 20V10 M10 20V4 M16 20v-7 M22 20H2" stroke_width="1.8" />
        Network overview
      </.link>
      <div class="grow"></div>
      <.link
        navigate="/"
        class={[side_link(false), "border-t border-[#EEF1EF] mt-2 !pt-3.5 rounded-t-none"]}
      >
        <.stroke_icon class="size-[17px]" d="M15 18l-6-6 6-6" stroke_width="1.8" /> Back to site
      </.link>
    </nav>
    """
  end

  defp side_link(active?) do
    [
      "flex items-center gap-[11px] px-[13px] py-[9px] rounded-[9px] text-[13.5px]",
      if(active?,
        do: "bg-route-soft text-route-deep font-semibold",
        else: "text-[#5C665F] font-medium hover:bg-[#EAF1EE] hover:text-ink"
      )
    ]
  end

  @doc "Header button that starts a fresh intake."
  attr :label, :string, required: true

  def start_over_link(assigns) do
    ~H"""
    <.link
      id="start-over"
      navigate="/start"
      aria-label={@label}
      title={@label}
      class="flex items-center gap-1.5 h-9 px-2.5 rounded-[10px] border border-line text-ink-muted hover:bg-[#EAF1EE] text-[12.5px] font-semibold"
    >
      <.stroke_icon class="size-4" d="M4 4v5h5 M4.6 15a8 8 0 1 0 1.9-8.3L4 9" />
      <span class="hidden sm:inline">{@label}</span>
    </.link>
    """
  end

  @doc "White patient-page header: back button, logo, and a centered middle slot."
  attr :back, :string, required: true
  attr :back_label, :string, required: true
  slot :inner_block, required: true
  slot :actions, doc: "Right-hand buttons; keeps the middle centered when empty"

  def patient_header(assigns) do
    ~H"""
    <header class="flex items-center gap-[14px] sm:gap-[18px] px-4 sm:px-9 py-4 border-b border-line bg-white">
      <.link
        navigate={@back}
        aria-label={@back_label}
        class="flex items-center justify-center size-9 rounded-[10px] border border-line text-ink-muted hover:bg-[#EAF1EE] shrink-0"
      >
        <.stroke_icon class="size-4" d="M15 6l-6 6 6 6" />
      </.link>
      <div class="hidden sm:flex items-center gap-2 shrink-0">
        <.logo_icon class="size-5 text-route" />
        <span class="font-display font-semibold text-[15px]">CareRoute AI</span>
      </div>
      <div class="grow min-w-0">{render_slot(@inner_block)}</div>
      <div :if={@actions == []} class="w-9 shrink-0"></div>
      <div :if={@actions != []} class="shrink-0">{render_slot(@actions)}</div>
    </header>
    """
  end
end
