import { Controller } from "@hotwired/stimulus"

// Issue #11: a tiny toolbar that inserts markdown emphasis tokens (**bold**, *italic*,
// _underline_) around the current textarea selection. The tokens are parsed SERVER-SIDE
// at render time by HujahsHelper#format_body — this controller only edits plain text, it
// never renders HTML, so it adds no XSS surface. Bodies stay plain text (the user sees
// the literal tokens while typing; no WYSIWYG — the accepted tradeoff).
//
// It shares the `field` textarea with the co-resident `composer` / `argument-composer`
// controllers (multiple controllers may target one element). After editing the value we
// dispatch a native `input` event so their char-counters and send-button gating re-run,
// exactly as if the user had typed.
export default class extends Controller {
  static targets = ["field"]

  bold() { this.wrap("**", "**") }
  italic() { this.wrap("*", "*") }
  underline() { this.wrap("_", "_") }

  wrap(open, close) {
    if (!this.hasFieldTarget) return
    const el = this.fieldTarget
    const start = el.selectionStart ?? el.value.length
    const end = el.selectionEnd ?? el.value.length
    const selected = el.value.slice(start, end)

    el.value = el.value.slice(0, start) + open + selected + close + el.value.slice(end)

    // With a selection, re-select the wrapped text; with none, drop the caret between
    // the inserted pair so the next keystroke lands inside the emphasis.
    const caret = start + open.length
    el.focus()
    if (selected.length) {
      el.setSelectionRange(caret, caret + selected.length)
    } else {
      el.setSelectionRange(caret, caret)
    }

    // Let the composer counters / send-button state update.
    el.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
