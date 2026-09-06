import { Controller } from "@hotwired/stimulus"

// The sticky argument bar on a single hoojah. Three states:
//   locked    — the viewer hasn't voted yet (mirrors HujahPolicy#create?, which
//               requires a prior vote before replying). Shows "Vote to join the
//               argument" + a JS-off fallback link to the full-page respond form.
//   collapsed — a pill; tapping it expands the composer.
//   expanded  — stance row + textarea + Send (a real form_with POST /hoojah).
//
// `voted` is set server-side and re-rendered true by votes/create.turbo_stream.erb
// after an inline vote, so casting a vote in the hero unlocks the bar. With JS off the
// state `hidden` attributes are whatever the server rendered and the fallback link works.
export default class extends Controller {
  static targets = ["locked", "collapsed", "expanded", "pill", "body", "send", "stanceField", "stanceBtn"]
  static values = { voted: Boolean }

  connect() {
    this.render()
    // Reflect the pre-seeded stance (the viewer's current vote) so a button reads as
    // selected the moment the composer opens, not only after a click.
    if (this.hasStanceFieldTarget) this.paintStance(this.stanceFieldTarget.value)
  }

  unlock() { this.votedValue = true; this.render() } // called after an inline vote

  expand() {
    this.state = "expanded"
    this.render()
    if (this.hasBodyTarget) this.bodyTarget.focus()
  }

  collapse() { this.state = "collapsed"; this.render() }

  pickStance(event) {
    const value = event.currentTarget.dataset.value
    if (this.hasStanceFieldTarget) this.stanceFieldTarget.value = value
    this.paintStance(value) // visual feedback: fill the picked stance, hollow the rest
    this.expand()
    this.input()
  }

  // Toggle each stance button between hollow (border + stance text on card bg) and
  // filled (solid stance bg + white glyph). The concrete bg-<stance>/text-white classes
  // are @source inline-safelisted in application.css, so string-built names still compile.
  paintStance(value) {
    if (!this.hasStanceBtnTarget) return
    this.stanceBtnTargets.forEach((btn) => {
      const stance = btn.dataset.stance
      const on = btn.dataset.value === String(value)
      btn.classList.toggle(`bg-${stance}`, on)
      btn.classList.toggle("text-white", on)
      btn.classList.toggle("bg-card", !on)
      btn.classList.toggle(`text-${stance}`, !on)
      btn.setAttribute("aria-pressed", on ? "true" : "false")
    })
  }

  // The maximize link hands the in-progress draft to the full-page composer. Rewrite its
  // href with the typed body + picked stance so the full form rehydrates instead of
  // opening blank. Full navigation (the full composer is turbo:false anyway).
  openFull(event) {
    event.preventDefault()
    const url = new URL(event.currentTarget.getAttribute("href"), window.location.origin)
    if (this.hasBodyTarget && this.bodyTarget.value.trim()) url.searchParams.set("body", this.bodyTarget.value)
    if (this.hasStanceFieldTarget && this.stanceFieldTarget.value) url.searchParams.set("vote", this.stanceFieldTarget.value)
    window.location.assign(url.toString())
  }

  input() {
    if (!this.hasSendTarget || !this.hasBodyTarget) return
    const stance = this.hasStanceFieldTarget ? this.stanceFieldTarget.value : "1"
    const ok = this.bodyTarget.value.trim().length > 0 && !!stance
    this.sendTarget.disabled = !ok
  }

  render() {
    const locked = !this.votedValue
    if (this.hasLockedTarget) this.lockedTarget.hidden = !locked
    const state = this.state || "collapsed"
    if (this.hasCollapsedTarget) this.collapsedTarget.hidden = locked || state !== "collapsed"
    if (this.hasExpandedTarget) this.expandedTarget.hidden = locked || state !== "expanded"
  }
}
