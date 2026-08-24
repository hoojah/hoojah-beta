import { Controller } from "@hotwired/stimulus"

// The sticky argument bar on a single hoojah. Three states:
//   locked    — the viewer hasn't voted yet (mirrors HujahPolicy#create?, which
//               requires a prior vote before replying). Shows "Vote to join the
//               argument" + a JS-off fallback link to the full-page respond form.
//   collapsed — a pill; tapping it expands the composer.
//   expanded  — stance row + textarea + Send (a real form_with POST /hoojah).
//
// `voted` is set server-side and re-rendered true by votes/create.turbo_stream.erb
// after an inline vote, so casting a vote in the hero unlocks the bar. With JS off the
// state `hidden` attributes are whatever the server rendered and the fallback link works.
export default class extends Controller {
  static targets = ["locked", "collapsed", "expanded", "pill", "body", "send", "stanceField"]
  static values = { voted: Boolean }

  connect() { this.render() }

  unlock() { this.votedValue = true; this.render() } // called after an inline vote

  expand() {
    this.state = "expanded"
    this.render()
    if (this.hasBodyTarget) this.bodyTarget.focus()
  }

  collapse() { this.state = "collapsed"; this.render() }

  pickStance(event) {
    if (this.hasStanceFieldTarget) this.stanceFieldTarget.value = event.currentTarget.dataset.value
    this.expand()
    this.input()
  }

  input() {
    if (!this.hasSendTarget || !this.hasBodyTarget) return
    const stance = this.hasStanceFieldTarget ? this.stanceFieldTarget.value : "1"
    const ok = this.bodyTarget.value.trim().length > 0 && !!stance
    this.sendTarget.disabled = !ok
  }

  render() {
    const locked = !this.votedValue
    if (this.hasLockedTarget) this.lockedTarget.hidden = !locked
    const state = this.state || "collapsed"
    if (this.hasCollapsedTarget) this.collapsedTarget.hidden = locked || state !== "collapsed"
    if (this.hasExpandedTarget) this.expandedTarget.hidden = locked || state !== "expanded"
  }
}
