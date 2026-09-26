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

  @doc "White patient-page header: back button, logo, and a centered middle slot."
  attr :back, :string, required: true
  attr :back_label, :string, required: true
  slot :inner_block, required: true

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
      <div class="w-9 shrink-0"></div>
    </header>
    """
  end
end
