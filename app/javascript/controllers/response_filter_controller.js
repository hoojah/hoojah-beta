import { Controller } from "@hotwired/stimulus"

// Client-side response filter for the single-hujah page. No fetch, no re-render —
// it just shows/hides the already-rendered child cards by toggling the `hidden`
// attribute, and reflects the active tab via aria-pressed.
//
// Contract (data attributes wired in _response_filter.html.erb / _child_card.html.erb):
//   tabs:  data-response-filter-target="tab" + data-response-filter-filter-param="<filter>"
//   items: data-response-filter-target="item" + data-response-filter-vote="<stance>"
//   empty: data-response-filter-target="empty" — placeholder shown when the active
//          filter matches zero items (only inside the "there ARE responses" branch;
//          the all-zero case is covered server-side by `responses_empty`).
export default class extends Controller {
  static targets = ["tab", "item", "empty"]
  static values = { active: { type: String, default: "all" } }

  filter(event) {
    this.activeValue = event.params.filter
  }

  activeValueChanged() {
    this.applyFilter()
  }

  // A response appended via Turbo Stream (create.turbo_stream.erb) connects a new
  // `item` target AFTER the last activeValueChanged. Re-apply the active filter to
  // the whole set so the new card is hidden/shown correctly and the placeholder
  // re-evaluates — otherwise a non-matching reply leaks into a filtered view, or a
  // matching reply leaves the "no matches" placeholder stranded.
  itemTargetConnected() {
    this.applyFilter()
  }

  // Invariant: `item` visibility is controlled SOLELY by this controller. If a future
  // change hides a card for another reason, the `visible === 0` guard below misfires.
  applyFilter() {
    const value = this.activeValue
    let visible = 0
    this.itemTargets.forEach((el) => {
      const show = value === "all" || el.dataset.responseFilterVote === value
      el.toggleAttribute("hidden", !show)
      if (show) visible += 1
    })
    if (this.hasEmptyTarget) {
      this.emptyTarget.toggleAttribute("hidden", !(visible === 0 && this.itemTargets.length > 0))
    }
    this.tabTargets.forEach((tab) => {
      tab.setAttribute("aria-pressed", String(tab.dataset.responseFilterFilterParam === value))
    })
  }
}
