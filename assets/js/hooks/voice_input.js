// Voice answers for the intake chat, using the browser's speech recognition.
//
// Speech is written into the message box as the patient talks, so they can
// check and correct it before pressing send. The answer is marked as spoken
// (hidden input_mode=voice) so clinicians know it came from speech recognition.
// Browsers without speech recognition keep the button hidden: typing only.
//
// Hook -> server: "voice-error" {error} when recognition fails.
const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition

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

  destroyed() {
    this.stop({discard: true})
    this.form?.removeEventListener("submit", this.onSubmit)
  },

  field(name) {
    return this.form.querySelector(`input[name="${name}"]`)
  },

  start() {
    const input = this.field("message")
    if (!input || input.disabled) return

    // Don't let the microphone pick up questions being read aloud.
    window.speechSynthesis?.cancel()

    const rec = new Recognition()
    rec.lang = this.el.dataset.lang
    rec.interimResults = true
    rec.continuous = false // ends after the patient pauses

    // Keep anything already typed; speech is appended to it.
    const typed = input.value.trim() ? input.value.trimEnd() + " " : ""

    rec.onresult = e => {
      if (rec !== this.rec) return
      const spoken = Array.from(e.results, r => r[0].transcript).join("")
      input.value = typed + spoken
      this.field("input_mode").value = "voice"
    }
    rec.onerror = e => {
      if (rec === this.rec && e.error !== "aborted") this.pushEvent("voice-error", {error: e.error})
    }
    rec.onend = () => {
      if (rec === this.rec) this.stop()
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
    const input = this.field("message")
    if (input && !discard) {
      input.placeholder = this.placeholder || input.placeholder
      input.focus()
    }
  },

  setPressed(on) {
    const label = on ? this.el.dataset.labelStop : this.el.dataset.labelStart
    this.button.setAttribute("aria-pressed", String(on))
    this.button.setAttribute("aria-label", label)
    this.button.title = label
  },
}
