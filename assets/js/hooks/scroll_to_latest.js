// Keeps the newest chat message in view as messages arrive.
export default {
  mounted() { this.scroll("auto") },
  updated() { this.scroll("smooth") },
  scroll(behavior) {
    this.el.lastElementChild?.scrollIntoView({behavior, block: "center"})
  },
}
