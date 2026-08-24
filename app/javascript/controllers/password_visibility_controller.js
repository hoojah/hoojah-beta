import { Controller } from "@hotwired/stimulus"

// The inline eye/eye-off reveal toggle on password fields (Hoojah 2026, Phase
// 1.1). Deliberately dumb: it flips `field.type` between "password" and "text"
// and toggles which of two PRE-RENDERED icons is visible via `hidden` — it never
// names a Lucide icon itself, so which glyph means "show" vs "hide" lives entirely
// in the view, not here.
//
// Contract (wired per field-row in the devise views):
//   wrapper: data-controller="password-visibility"
//   field:   data-password-visibility-target="field"
//   button:  type="button" data-action="password-visibility#toggle"
//   icons:   data-password-visibility-target="showIcon" / "hideIcon"
//            (hideIcon starts `hidden`; toggle() flips both together)
//
// Each field row on a page (log-in has one, sign-up has two) carries its own
// `data-controller` on its own wrapper, so Stimulus scopes `field`/`showIcon`/
// `hideIcon` per-instance — two password fields on the same page never see each
// other's targets.
//
// Progressive enhancement, not a requirement: with JS off the field is a
// perfectly ordinary `type="password"` input and the toggle button (also JS-off
// inert) simply does nothing, which is the safe default for a password field.
export default class extends Controller {
  static targets = ["field", "showIcon", "hideIcon"]

  toggle() {
    const revealing = this.fieldTarget.type === "password"
    this.fieldTarget.type = revealing ? "text" : "password"

    if (this.hasShowIconTarget) this.showIconTarget.hidden = revealing
    if (this.hasHideIconTarget) this.hideIconTarget.hidden = !revealing
  }
}
