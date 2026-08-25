import { Controller } from "@hotwired/stimulus"

// Debounced live-suggest for the Discover search bar (data-controller lives on the
// <form> itself). JS-off safety: the <input> sits inside a plain GET <form> carrying
// `data-turbo-frame="search-results"`, so with this controller absent — or with JS
// disabled entirely — a normal Enter/submit still reaches SearchController#index and
// renders the same results via a full page load. This controller only adds "update
// as you type" on top of that: it debounces keystrokes and asks the FORM to
// (re)submit itself, exactly as a real submit would — it never builds a search_path
// string or pokes a frame's `src` directly, so it can never drift from the
// server-rendered route or bypass the frame Turbo already knows how to target.
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  queryChanged() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
