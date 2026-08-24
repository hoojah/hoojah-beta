import { Controller } from "@hotwired/stimulus"

// Progressive enhancement over the plain vote forms on the single-hoojah vote hero.
// Pointer-down starts a charge timer + ring; release before threshold submits a
// NORMAL vote (tap); holding to completion submits with conviction=1 (locked
// forever). With JS off, each stance <form> is an ordinary POST casting a normal vote.
//
// There is ONE controller on the vote-hero wrapper and THREE <form>s inside it (one
// per stance). The shared ring/overlay targets live on the wrapper; the per-form
// conviction hidden field is looked up INSIDE the submitting form, not via a target.
export default class extends Controller {
  static targets = ["ring", "overlay", "chargeNum", "chargeLabel"]
  static values = { duration: { type: Number, default: 900 }, locked: Boolean }

  start(event) {
    if (this.lockedValue) return
    this.form = event.currentTarget.closest("form")
    this.held = false
    this.t0 = performance.now()
    this.setChargeColor(event.currentTarget.dataset.chargeColor)
    this.setChargeLabel(event.currentTarget.dataset.stance)
    this.raf = requestAnimationFrame(this.tick.bind(this))
    this.timer = setTimeout(() => { this.held = true; this.commit(true) }, this.durationValue)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = false
  }

  tick(now) {
    const pct = Math.min(1, (now - this.t0) / this.durationValue)
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge", pct)
    if (this.hasChargeNumTarget) {
      this.chargeNumTarget.textContent = Math.max(0, Math.ceil((1 - pct) * 3))
    }
    if (pct < 1 && !this.held) this.raf = requestAnimationFrame(this.tick.bind(this))
  }

  end() {
    if (this.held) return // conviction already committed by the timer
    this.cancelCharge()
    this.commit(false) // quick tap -> normal vote
  }

  leave() { if (!this.held) this.cancelCharge() } // pointer left the button -> cancel, no vote

  cancelCharge() {
    clearTimeout(this.timer)
    cancelAnimationFrame(this.raf)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = true
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge", 0)
  }

  noMenu(event) { event.preventDefault() } // suppress the long-press context menu

  setChargeColor(color) {
    if (!color) return
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge-color", color)
    if (this.hasChargeNumTarget) this.chargeNumTarget.style.color = color
    if (this.hasChargeLabelTarget) this.chargeLabelTarget.style.color = color
  }

  setChargeLabel(stance) {
    if (this.hasChargeLabelTarget && stance) {
      this.chargeLabelTarget.textContent = `charging ${stance}`
    }
  }

  commit(conviction) {
    clearTimeout(this.timer)
    cancelAnimationFrame(this.raf)
    if (!this.form) return
    // Per-form hidden field (three forms under one controller — one per stance — so
    // look it up INSIDE this.form, not via a controller target).
    const field = this.form.querySelector('input[name="conviction"]')
    if (field) field.value = conviction ? "1" : ""
    this.form.requestSubmit()
  }
}
