import { Controller } from "@hotwired/stimulus"

// Minimal, presentational composer helper for the debate turn form. Its ONLY job
// is to focus the textarea when the composer renders — both on the initial page
// load AND after the Turbo-Stream `replace` that swaps the composer back in once
// it's the user's turn again. `connect()` fires in both cases (Stimulus connects
// controllers on stream-inserted nodes too), which also scrolls the field into
// view for free.
//
// Deliberately no auto-grow (CSS `field-sizing: content` handles that) and no
// empty-submit guard (native `required` + Turbo's in-flight submit-disable cover
// it) — no Values, no extra state.
export default class extends Controller {
  static targets = ["field"]

  connect() {
    this.fieldTarget.focus()
  }
}
