import { Controller } from "@hotwired/stimulus"

// Vote-hero "N vote(s)" roll-up (ui-polish-2026). Casting a vote replaces the whole
// hero via Turbo Stream (hujahs/_vote_hero.html.erb), so a freshly-connected instance
// has no memory of the number that was on screen a moment ago. We bridge that gap with
// sessionStorage, keyed by keyValue (the hujah's dom_id + "-votes" — stable across the
// replace, distinct per hujah, cleared with the tab).
//
// On connect: read the last-seen count for this key. If one exists AND it differs from
// the value just rendered by the server AND the visitor hasn't asked for reduced motion,
// tween old -> new over ~300ms. Otherwise (first-ever visit, no change, or reduced
// motion) render the final value immediately — which is also exactly what's already in
// the DOM before this controller ever connects, so JS-off/pre-connect is correct too.
// The roll only ever fires once, right after the visitor's own vote changed the count —
// never on an ordinary page load or scroll.
export default class extends Controller {
  static targets = ["value"]
  static values = { key: String, value: Number }

  connect() {
    const current = this.valueValue
    const previous = this.readPrevious()

    if (previous !== null && previous !== current && !this.prefersReducedMotion()) {
      this.animate(previous, current)
    } else {
      this.render(current)
    }

    this.writeCurrent(current)
  }

  disconnect() {
    if (this.raf) cancelAnimationFrame(this.raf)
  }

  prefersReducedMotion() {
    return !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches)
  }

  storageKey() {
    return `number-roll:${this.keyValue}`
  }

  readPrevious() {
    try {
      const raw = sessionStorage.getItem(this.storageKey())
      if (raw === null) return null
      const n = parseInt(raw, 10)
      return Number.isNaN(n) ? null : n
    } catch (_error) {
      return null // storage unavailable (private mode, quota, etc.) — degrade to no-roll
    }
  }

  writeCurrent(value) {
    try {
      sessionStorage.setItem(this.storageKey(), String(value))
    } catch (_error) {
      // non-fatal — just means the next connect won't find a prior value to roll from
    }
  }

  animate(from, to) {
    const duration = 300
    const start = performance.now()

    const step = (now) => {
      const t = Math.min(1, (now - start) / duration)
      const eased = 1 - Math.pow(1 - t, 3) // ease-out cubic
      this.render(Math.round(from + (to - from) * eased))

      if (t < 1) {
        this.raf = requestAnimationFrame(step)
      } else {
        this.render(to) // guarantee we land exactly on the true value
      }
    }

    this.raf = requestAnimationFrame(step)
  }

  render(value) {
    if (this.hasValueTarget) this.valueTarget.textContent = value
  }
}
