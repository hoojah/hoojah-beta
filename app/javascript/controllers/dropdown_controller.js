import { Controller } from "@hotwired/stimulus"

// Dismiss a native `<details>` dropdown when the viewer taps/clicks anywhere outside
// it, or presses Escape. The design system builds its menus on `<details>`/`<summary>`
// (see ui/_menu) — which natively toggle on the summary but stay open on an outside
// click. This controller adds the expected "click away to close" behaviour without
// changing the JS-off contract: with JS disabled the <details> still opens and closes
// on the summary exactly as before.
//
// Attach to the `<details>` element itself:
//   <details data-controller="dropdown"> … </details>
//
// The document listeners are only live while the menu is open, and are torn down on
// disconnect so a cached Turbo snapshot can't leak a stuck listener.
export default class extends Controller {
  connect() {
    this.onDocClick = (event) => {
      if (!this.element.open) return
      if (this.element.contains(event.target)) return
      this.element.open = false
    }
    this.onKeydown = (event) => {
      if (event.key !== "Escape" || !this.element.open) return
      this.element.open = false
    }
    document.addEventListener("click", this.onDocClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKeydown)
  }
}
