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

  // The widget mounts its own iframe OUTSIDE this.element, so Stimulus's teardown
  // of the element does not remove it — without this, a disconnect/reconnect cycle
  // (Turbo cache restore reinserting the profile-edit wrapper) would leave the old
  // widget's DOM attached and connect() would build a second one. `destroy()` closes
  // the widget and removes it from the DOM; it returns a promise we don't await.
  //
  // Defensive on purpose: NOTHING in the suite reaches this branch. Cuprite
  // blacklists the Cloudinary host and the widget <script> is skipped in test, so
  // `window.cloudinary` is never defined and connect() always takes its early
  // return — a typo or an upstream API change here would surface only in
  // production, as a thrown error inside Turbo navigation.
  disconnect() {
    if (this.widget && typeof this.widget.destroy === "function") {
      try {
        this.widget.destroy({removeThumbnails: true})
      } catch (error) {
        // Never let third-party teardown break the Turbo visit.
      }
    }
    this.widget = null
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
