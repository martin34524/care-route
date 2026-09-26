defmodule CareRouteWeb.PageHTML do
  use CareRouteWeb, :html

  embed_templates "page_html/*"

  @steps [
    %{
      n: 1,
      title: "Tell us what’s going on",
      body: "Describe your symptoms in plain language — no medical terms required.",
      icon: "M4 4.5h16V16H9l-5 4.5z M8.5 9l1.7 1.7L13.5 8"
    },
    %{
      n: 2,
      title: "Answer a few smart questions",
      body: "Adaptive follow-ups narrow down urgency in under two minutes.",
      icon:
        "M12 3v6 M12 9 6 14 M12 9l6 5 M6 14a2 2 0 1 0 0 4 2 2 0 0 0 0-4z M18 14a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"
    },
    %{
      n: 3,
      title: "Get matched to the right care",
      body:
        "See the right level of care and nearby facilities on a map, then send your details ahead.",
      icon:
        "M12 3a7 7 0 0 0-7 7c0 5 7 11 7 11s7-6 7-11a7 7 0 0 0-7-7z M12 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6z"
    }
  ]

  @clinician_points [
    "Full adaptive Q&A transcript with every referral",
    "AI handoff summary with suggested urgency and danger signs",
    "New referrals appear live — accept them in one click"
  ]

  # Badge colors per CareRoute urgency level.
  @preview_rows [
    %{
      patient: "Patient #4471",
      complaint: "Abdominal pain, 2 days",
      level: "Clinic",
      bg: "#FBF3EA",
      fg: "#9A6B1F"
    },
    %{
      patient: "Patient #4472",
      complaint: "Sore throat, mild fever",
      level: "Self-care",
      bg: "#E4F1EE",
      fg: "#175650"
    },
    %{
      patient: "Patient #4473",
      complaint: "Chest tightness",
      level: "Urgent",
      bg: "#FBEAE6",
      fg: "#A23F26"
    }
  ]

  def steps, do: @steps
  def clinician_points, do: @clinician_points
  def preview_rows, do: @preview_rows
end
