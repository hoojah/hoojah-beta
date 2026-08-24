import { Controller } from "@hotwired/stimulus"

// Toggles data-theme (light/dark) and cycles data-scheme (spectrum/signal/ballot)
// on <html>, persisting both to localStorage. The no-FOUC head script re-applies
// them before paint on the next load, so a persisted choice survives a full reload
// (and, since <html> is not replaced by Turbo, survives Turbo visits without JS).
export default class extends Controller {
  static targets = ["toggle", "scheme"]
  static schemes = ["spectrum", "signal", "ballot"]

  toggleTheme() {
    const el = document.documentElement
    const next = el.getAttribute("data-theme") === "dark" ? "light" : "dark"
    el.setAttribute("data-theme", next)
    try { localStorage.setItem("hoojah-theme", next) } catch (e) {}
  }

  cycleScheme() {
    const el = document.documentElement
    const schemes = this.constructor.schemes
    const cur = el.getAttribute("data-scheme") || "spectrum"
    const next = schemes[(schemes.indexOf(cur) + 1) % schemes.length]
    el.setAttribute("data-scheme", next)
    try { localStorage.setItem("hoojah-scheme", next) } catch (e) {}
  }
}
