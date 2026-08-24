import { Controller } from "@hotwired/stimulus"

// Generic live "n / max" echo for a single textarea/input — progressive
// enhancement only. `maxlength` on the field is the real constraint and works
// with JS off; this just mirrors it the way the mockup shows it. No values, no
// state beyond what the field itself already carries.
export default class extends Controller {
  static targets = ["input", "count"]

  connect() { this.update() }

  update() {
    if (!this.hasInputTarget || !this.hasCountTarget) return
    const max = this.inputTarget.maxLength
    this.countTarget.textContent = `${this.inputTarget.value.length} / ${max}`
  }
}
