import { Controller } from "@hotwired/stimulus"

// Native <dialog> modal behavior, shared by profile-edit + flag (same behavior,
// different content). The wrapper element holds the trigger + the <dialog>.
//
// Contract (data attributes wired in the partials):
//   wrapper: data-controller="dialog"
//   trigger: data-action="dialog#open"
//   <dialog data-dialog-target="dialog"
//           data-action="click->dialog#backdropClose close->dialog#restoreFocus">
//   close button inside: data-action="dialog#close"
//
// showModal() (not show()) is required for the backdrop, top-layer stacking, Esc
// dismissal, and `inert`-ing the rest of the page. Backdrop-click close is NOT
// native, so we detect a click landing on the dialog element itself. Focus is
// restored to whatever was focused when the dialog opened (fires for Esc, backdrop,
// or a programmatic close). `teardown` is invoked by the one-time
// turbo:before-cache loop in application.js so a cached page never restores an
// open modal.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.previouslyFocused = document.activeElement
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }

  restoreFocus() {
    if (this.previouslyFocused && this.previouslyFocused.focus) {
      this.previouslyFocused.focus()
    }
  }

  teardown() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }
}
