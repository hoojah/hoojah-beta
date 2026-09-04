import { Controller } from "@hotwired/stimulus"

// Progressive enhancement over the plain vote forms on the single-hoojah vote hero.
// A quick TAP (release before `tap` ms) submits a NORMAL vote. A HOLD engages the
// conviction charge: a silent ARM phase (`armDelay` ms, no countdown digit) followed by
// a COUNTDOWN (`countdown` ms) showing 5→1, one digit per second; holding to the end
// commits conviction=1 (locked forever). Releasing OR leaving the button after the charge
// has engaged (past the tap threshold, before the lock) CANCELS with no vote at all.
// With JS off, each stance <form> is an ordinary POST casting a normal vote.
//
// ONE controller on the vote-hero wrapper, THREE <form>s inside (one per stance). The
// shared ring/overlay targets live on the wrapper; the per-form conviction hidden field
// is looked up INSIDE the submitting form, not via a target. Timing values are read from
// data-* attributes so system specs can shrink them to keep the suite fast.
export default class extends Controller {
  static targets = ["ring", "overlay", "chargeNum", "chargeLabel"]
  static values = {
    armDelay: { type: Number, default: 2000 },
    countdown: { type: Number, default: 5000 },
    tap: { type: Number, default: 200 },
    locked: Boolean
  }

  get totalMs() { return this.armDelayValue + this.countdownValue }

  start(event) {
    if (this.lockedValue) return
    this.form = event.currentTarget.closest("form")
    this.held = false
    this.t0 = performance.now()
    this.setChargeColor(event.currentTarget.dataset.chargeColor)
    this.setChargeLabel(event.currentTarget.dataset.stance)
    if (this.hasChargeNumTarget) this.chargeNumTarget.textContent = ""
    this.raf = requestAnimationFrame(this.tick.bind(this))
    this.timer = setTimeout(() => { this.held = true; this.commit(true) }, this.totalMs)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = false
  }

  tick(now) {
    const elapsed = now - this.t0
    // Ring reflects COUNTDOWN progress only; it stays at 0 through the arm phase.
    const charge = Math.min(1, Math.max(0, (elapsed - this.armDelayValue) / this.countdownValue))
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge", charge)
    if (this.hasChargeNumTarget) {
      // Blank during the arm phase; 5→1 during the countdown (each digit exactly 1s).
      this.chargeNumTarget.textContent =
        elapsed < this.armDelayValue ? "" : String(Math.max(1, Math.ceil((this.totalMs - elapsed) / 1000)))
    }
    if (elapsed < this.totalMs && !this.held) this.raf = requestAnimationFrame(this.tick.bind(this))
  }

  end() {
    if (this.held) return // conviction already committed by the timer
    const quickTap = (performance.now() - this.t0) < this.tapValue
    this.cancelCharge()
    if (quickTap) this.commit(false) // quick tap -> normal vote; a longer hold -> cancel, no vote
  }

  leave() { if (!this.held) this.cancelCharge() } // pointer left the button -> cancel, no vote

  cancelCharge() {
    clearTimeout(this.timer)
    cancelAnimationFrame(this.raf)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = true
    if (this.hasRingTarget) this.ringTarget.style.setProperty("--charge", 0)
    if (this.hasChargeNumTarget) this.chargeNumTarget.textContent = ""
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
