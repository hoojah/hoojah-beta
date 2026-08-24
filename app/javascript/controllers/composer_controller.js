import { Controller } from "@hotwired/stimulus"

// Drives both composer variants (full-page + inline feed). Progressive enhancement:
// the <form> submits fine with JS off; this only gates the Post button, inserts hashtag
// chips, and expands the inline pill. Visibility is a native <select> (the `select`
// target) — the canonical, always-submitted control, so it needs no JS to work.
export default class extends Controller {
  static targets = ["body", "post", "select", "collapsed", "expanded"]
  static values = { min: { type: Number, default: 8 }, requireMin: { type: Boolean, default: true } }

  connect() { this.sync() }

  sync() {
    if (!this.hasPostTarget || !this.hasBodyTarget) return
    const ok = !this.requireMinValue || this.bodyTarget.value.trim().length >= this.minValue
    this.postTarget.disabled = !ok
    this.postTarget.toggleAttribute("data-ready", ok)
  }

  input() { this.sync(); this.autogrow() }

  autogrow() {
    const el = this.bodyTarget
    el.style.height = "auto"
    el.style.height = el.scrollHeight + "px"
  }

  addTag(event) {
    event.preventDefault()
    const tag = event.currentTarget.dataset.tag
    const el = this.bodyTarget
    const sep = el.value.length && !el.value.endsWith(" ") ? " " : ""
    el.value = el.value + sep + "#" + tag + " "
    el.focus()
    this.sync(); this.autogrow()
  }

  expand() { if (this.hasCollapsedTarget) { this.collapsedTarget.hidden = true; this.expandedTarget.hidden = false; this.bodyTarget.focus() } }
}
