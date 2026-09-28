// Map of the facilities offered to the patient, numbered to match the list.
//
// Server -> hook: "facility-map:update" {facilities, origin}, "facility-map:select" {id}
// Hook -> server: "located" {lat, lng}, "refer" {"facility-id": id}
import * as L from "../../vendor/leaflet/leaflet-src.esm.js"

export default {
  mounted() {
    this.facilities = JSON.parse(this.el.dataset.facilities)
    this.origin = JSON.parse(this.el.dataset.origin)
    // Translated "Go here" and facility type labels, in the patient's language.
    this.labels = JSON.parse(this.el.dataset.labels)
    this.selectedId = null

    const mapEl = this.el.querySelector("[data-map]")
    this.map = L.map(mapEl, {scrollWheelZoom: false})
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(this.map)
    this.layer = L.layerGroup().addTo(this.map)
    this.render()

    // "Go here" buttons live inside Leaflet popups, outside LiveView's DOM.
    mapEl.addEventListener("click", e => {
      const button = e.target.closest("[data-refer]")
      if (button) this.pushEvent("refer", {"facility-id": button.dataset.refer})
    })

    this.handleEvent("facility-map:update", ({facilities, origin}) => {
      this.facilities = facilities
      this.origin = origin
      this.render()
    })

    this.handleEvent("facility-map:select", ({id}) => {
      this.selectedId = id
      this.render()
    })

    navigator.geolocation?.getCurrentPosition(
      ({coords}) => this.pushEvent("located", {lat: coords.latitude, lng: coords.longitude}),
      () => {}, // Denied or unavailable: keep the demo location.
      {timeout: 10000, maximumAge: 300000}
    )
  },

  destroyed() {
    this.map.remove()
  },

  render() {
    this.layer.clearLayers()
    const shown = this.selectedId
      ? this.facilities.filter(f => f.id === this.selectedId)
      : this.facilities
    const points = []

    this.facilities.forEach((f, i) => {
      if (f.lat == null || !shown.includes(f)) return
      const icon = L.divIcon({
        className: "",
        html: `<span class="map-pin map-pin-${f.type}">${i + 1}</span>`,
        iconSize: [28, 28],
        iconAnchor: [14, 14],
        popupAnchor: [0, -14],
      })
      const marker = L.marker([f.lat, f.lng], {icon, title: f.name})
        .bindPopup(() => this.popup(f))
        .addTo(this.layer)
      if (this.selectedId) marker.openPopup()
      points.push([f.lat, f.lng])
    })

    const {lat, lng, source} = this.origin
    L.circleMarker([lat, lng], {radius: 8, color: "#fff", weight: 3, fillColor: "#2563eb", fillOpacity: 1})
      .bindTooltip(source === "device" ? "You are here" : "Demo location")
      .addTo(this.layer)
    points.push([lat, lng])

    this.map.fitBounds(points, {padding: [32, 32], maxZoom: 15})
  },

  // Built with DOM APIs (not HTML strings) so facility data is never parsed as markup.
  popup(f) {
    const root = document.createElement("div")
    const add = (tag, text, cls) => {
      const el = document.createElement(tag)
      el.textContent = text
      if (cls) el.className = cls
      root.appendChild(el)
      return el
    }
    add("strong", f.name)
    add("div", `${this.labels.types[f.type] || f.type} · ${f.distance_km} km`, "text-xs opacity-70")
    if (f.address) add("div", f.address, "text-xs")
    if (!f.partner) add("div", this.labels.not_connected, "text-xs opacity-70 mt-1")

    const actions = document.createElement("div")
    actions.className = "flex gap-2 mt-2"
    root.appendChild(actions)
    const action = (tag, text, cls) => {
      const el = document.createElement(tag)
      el.textContent = text
      el.className = cls
      actions.appendChild(el)
      return el
    }
    // Only partner facilities use CareRoute, so only they can receive a referral.
    if (f.partner && !this.selectedId) {
      action("button", this.labels.go, "bg-route hover:bg-route-dark text-white px-3 py-1 rounded-md text-xs font-semibold").dataset.refer = f.id
    }
    if (f.directions) {
      const link = action("a", this.labels.directions, "border border-line px-3 py-1 rounded-md text-xs font-semibold")
      link.href = f.directions
      link.target = "_blank"
      link.rel = "noopener noreferrer"
    }
    if (f.phone) {
      action("a", this.labels.call, "border border-line px-3 py-1 rounded-md text-xs font-semibold").href = "tel:" + f.phone.replace(/[^+0-9]/g, "")
    }
    return root
  },
}
