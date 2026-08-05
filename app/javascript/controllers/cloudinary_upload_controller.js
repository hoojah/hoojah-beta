import { Controller } from "@hotwired/stimulus"

// Drives the Cloudinary upload widget for the profile-edit photo field. The hidden
// input IS the state (no Values) — the visible <img> preview reacts to its `input`
// event. `window.cloudinary` is a global loaded via the layout <script> (Slice 1
// CSP `frame-src widget.cloudinary.com`), NOT an importmap module — so we guard for
// its absence (CSP/adblock/offline) and disable the trigger.
//
// Contract (data attributes wired in _profile_edit.html.erb):
//   wrapper: data-controller="cloudinary-upload"
//   trigger button: data-action="cloudinary-upload#open" +
//                   data-cloudinary-upload-target="button"
//   hidden field:   data-cloudinary-upload-target="hidden"
export default class extends Controller {
  static targets = ["hidden", "button"]

  connect() {
    if (!window.cloudinary) {
      if (this.hasButtonTarget) this.buttonTarget.disabled = true
      return
    }
    this.widget = window.cloudinary.createUploadWidget(
      { cloudName: "hoojah", uploadPreset: "user_photo", tags: ["user_photo"] },
      // ARROW fn — a bare method ref would bind `this` to the widget, not us.
      (error, result) => this.onUpload(error, result)
    )
  }

  open() {
    if (this.widget) this.widget.open()
  }

  onUpload(error, result) {
    if (error || !result || result.event !== "success") return
    this.hiddenTarget.value = result.info.secure_url
    // Bubbling `input` so the <img> preview (and any listeners) react.
    this.hiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
