// Minimal service worker so CareRoute can be installed to the home screen.
// It doesn't cache anything: every request goes to the network, so patients
// always get live answers and a stale page is never shown.
self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()))
self.addEventListener("fetch", () => {})
