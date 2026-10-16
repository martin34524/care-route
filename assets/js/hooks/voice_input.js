// Voice input using the browser's speech recognition.
//
// In the chat, speech is written into the message box as the patient talks, so
// they can check and correct it before pressing send. The answer is marked as
// spoken (hidden input_mode=voice) so clinicians know it came from speech
// recognition.
//
// On a form field (data-target = the input's id), speech replaces the field's
// value, cleaned up for the field's data-kind:
//   "name"   — drops "my name is…" and trailing punctuation
//   "number" — an age: digits or number words (English/Kiswahili); months or
//              weeks mean under one year, so 0
//   "tel"    — a phone number: digits or spoken digit words
// An "input" event is dispatched so phx-change sees the new value.
//
// Browsers without speech recognition keep the button hidden: typing only.
//
// Hook -> server: "voice-error" {error} when recognition fails, or
// "no-number" when no number was heard for a number field.
const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition

const UNITS = {
  zero: 0, oh: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8,
  nine: 9, ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15,
  sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19, twenty: 20, thirty: 30, forty: 40,
  fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90,
  sifuri: 0, moja: 1, mbili: 2, tatu: 3, nne: 4, tano: 5, sita: 6, saba: 7, nane: 8, tisa: 9,
  kumi: 10, ishirini: 20, thelathini: 30, arobaini: 40, hamsini: 50, sitini: 60, sabini: 70,
  themanini: 80, tisini: 90,
}

const words = text => text.toLowerCase().split(/[^\p{L}\p{N}+]+/u).filter(Boolean)

// "34", "thirty four", "miaka kumi na mbili", "six months" -> 34, 34, 12, 0
function parseAge(text) {
  if (/\b(months?|weeks?|days?|mwezi|miezi|wiki|siku)\b/i.test(text)) return 0
  const digits = text.match(/\d+/)
  if (digits) return Number(digits[0])

  let total = null
  for (const w of words(text)) {
    if (w === "hundred") total = (total || 1) * 100
    else if (w === "mia") total = (total || 0) + 100
    else if (w in UNITS && !(w === "moja" && total === 100)) total = (total || 0) + UNITS[w]
  }
  return total
}

// "+254 712 345678", "zero seven one two…" -> "+254712345678", "0712…"
function parsePhone(text) {
  let out = ""
  for (const w of words(text)) {
    if (w === "plus") out += "+"
    else if (/[\d+]/.test(w)) out += w.replace(/[^\d+]/g, "")
    else if (w in UNITS && UNITS[w] < 10) out += UNITS[w]
  }
  return out
}

function parseName(text) {
  return text
    .replace(/^\s*(my name is|i am|i'm|it's|jina langu ni|naitwa|mimi ni)\s+/i, "")
    .replace(/[.,!?]+\s*$/, "")
    .trim()
}

export default {
  mounted() {
    if (!Recognition) return

    this.form = this.el.closest("form")
    this.button = this.el.querySelector("button")
    this.el.classList.remove("hidden")

    this.button.addEventListener("click", () => (this.rec ? this.stop() : this.start()))

    // Sending mid-sentence discards anything still being recognized, so late
    // words can't land in the next (freshly rendered) message box.
    this.onSubmit = () => this.stop({discard: true})
    this.form.addEventListener("submit", this.onSubmit)
  },

  // Picking another language re-renders the data-* labels; keep the button in step.
  updated() {
    if (this.button && !this.rec) this.setPressed(false)
  },

  destroyed() {
    this.stop({discard: true})
    this.form?.removeEventListener("submit", this.onSubmit)
  },

  field(name) {
    return this.form.querySelector(`input[name="${name}"]`)
  },

  input() {
    const target = this.el.dataset.target
    return target ? document.getElementById(target) : this.field("message")
  },

  start() {
    const input = this.input()
    if (!input || input.disabled) return

    // Don't let the microphone pick up questions being read aloud.
    window.speechSynthesis?.cancel()

    const rec = new Recognition()
    rec.lang = this.el.dataset.lang
    rec.interimResults = true
    rec.continuous = false // ends after the patient pauses

    const kind = this.el.dataset.kind
    // In the chat, keep anything already typed; speech is appended to it.
    const typed = !kind && input.value.trim() ? input.value.trimEnd() + " " : ""
    let heard = ""

    rec.onresult = e => {
      if (rec !== this.rec) return
      heard = Array.from(e.results, r => r[0].transcript).join("")
      const finished = e.results[e.results.length - 1].isFinal

      if (kind === "number") {
        // A number box can't show half a sentence; fill it once speech ends.
        if (!finished) return
        const age = parseAge(heard)
        if (age === null) return
        input.value = String(age)
      } else if (kind === "tel") {
        input.value = parsePhone(heard)
      } else if (kind === "name") {
        input.value = parseName(heard)
      } else {
        input.value = typed + heard
      }

      // maxlength only limits typing, so trim dictated text to it too.
      if (input.maxLength > 0) input.value = input.value.slice(0, input.maxLength)
      const mode = this.field("input_mode")
      if (mode) mode.value = "voice"
      if (kind) input.dispatchEvent(new Event("input", {bubbles: true}))
    }
    rec.onerror = e => {
      if (rec === this.rec && e.error !== "aborted") this.pushEvent("voice-error", {error: e.error})
    }
    rec.onend = () => {
      if (rec !== this.rec) return
      if (kind === "number" && heard && parseAge(heard) === null) {
        this.pushEvent("voice-error", {error: "no-number"})
      }
      this.stop()
    }

    this.rec = rec
    this.placeholder = input.placeholder
    input.placeholder = this.el.dataset.labelListening
    this.setPressed(true)

    try {
      rec.start()
    } catch (_e) {
      this.stop()
      this.pushEvent("voice-error", {error: "start-failed"})
    }
  },

  stop({discard = false} = {}) {
    const rec = this.rec
    if (!rec) return
    this.rec = null
    discard ? rec.abort() : rec.stop()

    this.setPressed(false)
    const input = this.input()
    if (input) {
      input.placeholder = this.placeholder ?? input.placeholder
      if (!discard) input.focus()
    }
  },

  setPressed(on) {
    const label = on ? this.el.dataset.labelStop : this.el.dataset.labelStart
    this.button.setAttribute("aria-pressed", String(on))
    this.button.setAttribute("aria-label", label)
    this.button.title = label
  },
}
