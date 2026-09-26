defmodule CareRoute.Intake.Phrases do
  @moduledoc """
  Fixed patient-facing messages that don't come from the AI, per language.
  AI-generated text is produced directly in the patient's language instead.
  """

  @languages %{"en" => "English", "sw" => "Kiswahili"}

  @phrases %{
    greeting: %{
      "en" =>
        "Hi, I’m CareRoute. I’m here to help you find the right care — I won’t diagnose " <>
          "anything, just point you in the right direction. What’s going on today?",
      "sw" =>
        "Habari, mimi ni CareRoute. Niko hapa kukusaidia kupata huduma sahihi — sitatambua " <>
          "ugonjwa wowote, nitakuelekeza tu mahali panapofaa. Kuna nini leo?"
    },
    urgent: %{
      "en" =>
        "Based on what you've shared, please seek urgent care now. " <>
          "If this is an emergency, call %{numbers} now.",
      "sw" =>
        "Kutokana na ulichoeleza, tafadhali tafuta huduma ya dharura sasa hivi. " <>
          "Ikiwa ni dharura, piga simu %{numbers} sasa hivi."
    },
    ready: %{
      "en" => "Thanks — that’s everything I need. I have a recommendation ready for you.",
      "sw" =>
        "Asante — hizo ndizo taarifa zote ninazohitaji. Nina pendekezo tayari kwa ajili yako."
    },
    # Start screen
    start_title: %{"en" => "Before we start", "sw" => "Kabla hatujaanza"},
    start_subtitle: %{
      "en" =>
        "A few details help CareRoute point you to the right care. It takes about three minutes.",
      "sw" =>
        "Taarifa chache zitasaidia CareRoute kukuelekeza kwenye huduma sahihi. Inachukua takriban dakika tatu."
    },
    field_language: %{"en" => "Language", "sw" => "Lugha"},
    field_name: %{"en" => "Name (optional)", "sw" => "Jina (si lazima)"},
    field_age: %{
      "en" => "Age of the person who needs care",
      "sw" => "Umri wa mtu anayehitaji huduma"
    },
    consent: %{
      "en" =>
        "I understand CareRoute doesn't diagnose, and that my answers are shared with the facility I choose.",
      "sw" =>
        "Ninaelewa kwamba CareRoute haitambui magonjwa, na kwamba majibu yangu yatashirikiwa na kituo nitakachochagua."
    },
    privacy_link: %{
      "en" => "How we use your information",
      "sw" => "Jinsi tunavyotumia taarifa zako"
    },
    start: %{"en" => "Start", "sw" => "Anza"},
    consent_required: %{
      "en" => "Please tick the box to continue.",
      "sw" => "Tafadhali weka alama kwenye kisanduku ili kuendelea."
    },
    age_invalid: %{
      "en" => "Enter an age between 0 and 129.",
      "sw" => "Weka umri kati ya 0 na 129."
    },
    start_over: %{"en" => "Start over", "sw" => "Anza upya"},
    # Chat screen
    emergency_banner: %{
      "en" => "If this feels like a medical emergency, call %{numbers} now.",
      "sw" => "Ikiwa hii ni dharura ya kiafya, piga simu %{numbers} sasa hivi."
    },
    progress: %{"en" => "Question %{n} of %{total}", "sw" => "Swali %{n} kati ya %{total}"},
    almost_done: %{"en" => "almost done", "sw" => "karibu kumaliza"},
    progress_done: %{
      "en" => "Done · recommendation ready",
      "sw" => "Tayari · pendekezo liko tayari"
    },
    progress_urgent: %{
      "en" => "Urgent · please seek care now",
      "sw" => "Dharura · tafuta huduma sasa"
    },
    message_label: %{"en" => "Type your message", "sw" => "Andika ujumbe wako"},
    message_placeholder: %{"en" => "Type a message…", "sw" => "Andika ujumbe…"},
    closed_placeholder: %{
      "en" => "This conversation is complete",
      "sw" => "Mazungumzo haya yamekamilika"
    },
    send: %{"en" => "Send message", "sw" => "Tuma ujumbe"},
    back: %{"en" => "Back to home", "sw" => "Rudi mwanzo"},
    see_recommendation: %{"en" => "See my recommendation", "sw" => "Ona pendekezo langu"},
    ai_unavailable: %{
      "en" =>
        "Sorry — I'm having trouble connecting right now. Tap Try again, or send your " <>
          "answer again. If this is an emergency, call %{numbers}.",
      "sw" =>
        "Samahani — nina tatizo la kuunganisha sasa hivi. Bonyeza Jaribu tena, au tuma " <>
          "jibu lako tena. Ikiwa ni dharura, piga simu %{numbers}."
    },
    try_again: %{"en" => "Try again", "sw" => "Jaribu tena"},
    call_now: %{"en" => "Call %{number}", "sw" => "Piga %{number}"},
    or: %{"en" => "or", "sw" => "au"},
    # Voice answers
    voice_start: %{"en" => "Answer by voice", "sw" => "Jibu kwa sauti"},
    voice_stop: %{"en" => "Stop listening", "sw" => "Acha kusikiliza"},
    voice_listening: %{"en" => "Listening… speak now", "sw" => "Ninasikiliza… ongea sasa"},
    voice_spoken: %{"en" => "Spoken answer", "sw" => "Jibu la sauti"},
    voice_blocked: %{
      "en" =>
        "Microphone access is blocked. Allow it in your browser to answer by voice, or type your answer.",
      "sw" =>
        "Maikrofoni imezuiwa. Iruhusu kwenye kivinjari chako ili ujibu kwa sauti, au andika jibu lako."
    },
    voice_no_speech: %{
      "en" => "I didn't catch that. Try again, or type your answer.",
      "sw" => "Sikukusikia vizuri. Jaribu tena, au andika jibu lako."
    },
    voice_failed: %{
      "en" => "Voice input isn't working right now. Please type your answer.",
      "sw" => "Kujibu kwa sauti hakufanyi kazi sasa hivi. Tafadhali andika jibu lako."
    },
    # Results screen
    your_recommendation: %{"en" => "Your recommendation", "sw" => "Pendekezo lako"},
    back_to_chat: %{"en" => "Back to the conversation", "sw" => "Rudi kwenye mazungumzo"},
    recommended_level: %{
      "en" => "Recommended level of care",
      "sw" => "Kiwango cha huduma kinachopendekezwa"
    },
    care_self_care: %{"en" => "Self-care at home", "sw" => "Kujihudumia nyumbani"},
    care_clinic: %{"en" => "Clinic visit", "sw" => "Kutembelea kliniki"},
    care_urgent: %{"en" => "Urgent care", "sw" => "Huduma ya dharura"},
    urgency_self_care: %{
      "en" => "Low urgency · you can likely care for this at home",
      "sw" => "Dharura ndogo · huenda unaweza kujihudumia nyumbani"
    },
    urgency_clinic: %{
      "en" => "Moderate urgency · see a clinician soon",
      "sw" => "Dharura ya wastani · muone mhudumu wa afya hivi karibuni"
    },
    urgency_urgent: %{
      "en" => "High urgency · seek care now",
      "sw" => "Dharura kubwa · tafuta huduma sasa hivi"
    },
    not_a_diagnosis: %{
      "en" => "This is a recommendation, not a diagnosis.",
      "sw" => "Hili ni pendekezo, si utambuzi wa ugonjwa."
    },
    find_self_care: %{"en" => "Find a clinic near me", "sw" => "Tafuta kliniki karibu nami"},
    find_clinic: %{"en" => "Find a clinic near me", "sw" => "Tafuta kliniki karibu nami"},
    find_urgent: %{
      "en" => "Find urgent care near me",
      "sw" => "Tafuta huduma ya dharura karibu nami"
    },
    send_referral: %{
      "en" => "Send referral to a clinician",
      "sw" => "Tuma rufaa kwa mhudumu wa afya"
    },
    facilities_near: %{"en" => "Facilities near you", "sw" => "Vituo vilivyo karibu nawe"},
    sorted_by_distance: %{"en" => "Sorted by distance", "sw" => "Vimepangwa kwa umbali"},
    directions: %{"en" => "Get directions", "sw" => "Pata maelekezo"},
    request_referral: %{"en" => "Request referral", "sw" => "Omba rufaa"},
    referral_sent: %{
      "en" => "Referral sent to %{facility}. They'll have your details when you arrive.",
      "sw" => "Rufaa imetumwa kwa %{facility}. Watakuwa na taarifa zako utakapofika."
    },
    referral_sent_short: %{"en" => "Referral sent", "sw" => "Rufaa imetumwa"},
    emergency_24_7: %{"en" => "Emergency 24/7", "sw" => "Dharura saa 24"},
    disclaimer: %{
      "en" =>
        "CareRoute AI does not diagnose medical conditions. If your symptoms worsen or you " <>
          "believe this is an emergency, call %{numbers} immediately.",
      "sw" =>
        "CareRoute AI haitambui magonjwa. Dalili zako zikizidi au ukiamini ni dharura, " <>
          "piga simu %{numbers} mara moja."
    },
    type_clinic: %{"en" => "Clinic", "sw" => "Kliniki"},
    type_hospital: %{"en" => "Hospital", "sw" => "Hospitali"},
    type_specialist: %{"en" => "Specialist", "sw" => "Mtaalamu"},
    out_of_area: %{
      "en" => "You're outside the demo area, so distances are from a demo location.",
      "sw" => "Uko nje ya eneo la majaribio, kwa hivyo umbali unapimwa kutoka eneo la majaribio."
    }
  }

  def languages, do: @languages

  def language_name(code), do: Map.get(@languages, code, "English")

  @doc "The phrase in `language` (falling back to English), with emergency numbers filled in."
  def t(key, language) do
    text = @phrases |> Map.fetch!(key) |> Map.get(language, @phrases[key]["en"])

    if String.contains?(text, "%{numbers}"),
      do: String.replace(text, "%{numbers}", emergency_numbers_label(language)),
      else: text
  end

  @doc "The configured emergency numbers, e.g. [\"999\", \"112\"]."
  def emergency_numbers, do: Application.fetch_env!(:care_route, :emergency_numbers)

  @doc "The number used for tap-to-call links."
  def emergency_number, do: hd(emergency_numbers())

  # "999 or 112" / "999 au 112"
  defp emergency_numbers_label(language) do
    Enum.join(emergency_numbers(), " #{t(:or, language)} ")
  end

  @doc "Like `t/2`, replacing `%{name}` placeholders with `bindings`."
  def t(key, language, bindings) do
    Enum.reduce(bindings, t(key, language), fn {name, value}, text ->
      String.replace(text, "%{#{name}}", to_string(value))
    end)
  end
end
