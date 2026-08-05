import { Controller } from "@hotwired/stimulus"

// Web Share API wrapper (faithful successor to the legacy SPA share dropdown).
//
// The fallback intent-link menu (wa.me / x.com / t.me / reddit / facebook / mailto)
// is ALWAYS server-rendered and works with JS off. This controller only progressively
// enhances: on a device that supports `navigator.share` (chiefly mobile), it unhides a
// single native "Share" button that opens the OS share sheet.
//
// Contract (wired in _share_menu.html.erb):
//   wrapper: data-controller="share"
//            data-share-title-value / -text-value / -url-value
//   button:  hidden data-share-target="button" data-action="share#share"
export default class extends Controller {
  static targets = ["button"]
  static values = { title: String, text: String, url: String }

  connect() {
    // Feature-detect: only reveal the native button where the API exists.
    if ("share" in navigator && this.hasButtonTarget) {
      this.buttonTarget.hidden = false
    }
  }

  async share(event) {
    event.preventDefault()
    try {
      await navigator.share({
        title: this.titleValue,
        text: this.textValue,
        url: this.urlValue
      })
    } catch (error) {
      // The user dismissing the share sheet is not an error worth surfacing.
      if (error.name === "AbortError") return
      throw error
    }
  }
}
