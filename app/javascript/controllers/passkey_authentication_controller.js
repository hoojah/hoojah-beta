import { Controller } from "@hotwired/stimulus"
import { get } from "@github/webauthn-json"

// "Sign in with a passkey" on the login page. Usernameless: fetch a challenge,
// run navigator.credentials.get() (via webauthn-json), then POST the assertion
// FORM-ENCODED (the Warden strategy reads Rack-level params, which don't parse
// JSON). Progressive enhancement — hides itself when the browser lacks WebAuthn.
export default class extends Controller {
  static targets = ["error"]

  connect() {
    if (!window.PublicKeyCredential) this.element.hidden = true
  }

  async authenticate(event) {
    event.preventDefault()
    this.clearError()
    try {
      const options = await this.postForOptions("/login/passkey/options")
      const assertion = await get({ publicKey: options })

      const body = new URLSearchParams()
      body.set("credential", JSON.stringify(assertion))
      const response = await fetch("/login/passkey", {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken },
        body
      })
      if (!response.ok) throw new Error("verify failed")
      const data = await response.json()
      window.location = data.redirect
    } catch (_e) {
      this.showError("We couldn't verify that passkey. Try again or use your password.")
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
