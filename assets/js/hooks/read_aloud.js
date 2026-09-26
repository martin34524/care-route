// Reads the AI's questions aloud with the browser's speech synthesis.
//
// The patient turns it on with the speaker button; the choice is remembered
// in this browser. It's only offered when the device has a voice for the
// patient's language, since e.g. an English voice reading Kiswahili is worse
// than no voice at all.
//
// Server -> hook: "read-aloud" {text} for each new assistant message.
const synth = window.speechSynthesis
const STORAGE_KEY = "careroute:read-aloud"

export default {
  mounted() {
    if (!synth || !window.SpeechSynthesisUtterance) return

    this.lang = this.el.dataset.lang
    this.latest = this.el.dataset.latest
    this.button = this.el.querySelector("button")
    this.on = false

    this.button.addEventListener("click", () => this.toggle())
    this.handleEvent("read-aloud", ({text}) => {
      this.latest = text
      if (this.on) this.speak(text)
    })

    // Voices load asynchronously in some browsers.
    this.onVoices = () => this.setup()
    synth.addEventListener?.("voiceschanged", this.onVoices)
    this.setup()
  },

  destroyed() {
    synth?.cancel()
    synth?.removeEventListener?.("voiceschanged", this.onVoices)
  },

  setup() {
    this.voice = this.pickVoice()
    if (!this.voice) return
    this.el.classList.remove("hidden")
    if (!this.initialized) {
      this.initialized = true
      this.setOn(this.remembered())
    }
  },

  // Prefer the exact locale (sw-KE), then any voice for the language (sw).
  pickVoice() {
    const voices = synth.getVoices()
    const base = this.lang.split("-")[0].toLowerCase()
    return (
      voices.find(v => v.lang.toLowerCase() === this.lang.toLowerCase()) ||
      voices.find(v => v.lang.toLowerCase().startsWith(base))
    )
  },

  toggle() {
    this.setOn(!this.on)
    this.remember(this.on)
    if (this.on && this.latest) this.speak(this.latest)
  },

  setOn(on) {
    this.on = on
    if (!on) synth.cancel()
    const label = on ? this.el.dataset.labelOff : this.el.dataset.labelOn
    this.button.setAttribute("aria-pressed", String(on))
    this.button.setAttribute("aria-label", label)
    this.button.title = label
  },

  speak(text) {
    synth.cancel()
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.voice = this.voice
    utterance.lang = this.voice.lang
    synth.speak(utterance)
  },

  remembered() {
    try {
      return localStorage.getItem(STORAGE_KEY) === "on"
    } catch (_e) {
      return false
    }
  },

  remember(on) {
    try {
      localStorage.setItem(STORAGE_KEY, on ? "on" : "off")
    } catch (_e) {}
  },
}
