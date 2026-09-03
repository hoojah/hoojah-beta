import { Controller } from "@hotwired/stimulus"
import { create } from "@github/webauthn-json"

// Add-a-passkey on the security page. Fetch creation options, run
// navigator.credentials.create() (via webauthn-json), then POST the attestation
// as JSON (this hits an ordinary Rails controller, which parses JSON). The server
// replies with a Turbo Stream that appends the new row; we apply it by hand
// because this is a fetch, not a Turbo form submit.
export default class extends Controller {
  static targets = ["nickname", "error"]

  connect() {
    if (!window.PublicKeyCredential) {
      this.element.querySelectorAll("[data-passkey-add]").forEach((el) => (el.disabled = true))
    }
  }

  async add(event) {
    event.preventDefault()
    this.clearError()
    try {
      const options = await this.postForOptions("/settings/passkeys/options")
      const attestation = await create({ publicKey: options })
      const nickname = this.hasNicknameTarget ? this.nicknameTarget.value : ""

      const response = await fetch("/settings/passkeys", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ passkey: { credential: attestation, nickname } })
      })
      if (!response.ok) throw new Error("create failed")
      window.Turbo.renderStreamMessage(await response.text())
      if (this.hasNicknameTarget) this.nicknameTarget.value = ""
    } catch (_e) {
      this.showError("We couldn't add that passkey. Please try again.")
    }
  }

  async postForOptions(url) {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken }
    })
    if (!response.ok) throw new Error("options failed")
    return response.json()
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}
