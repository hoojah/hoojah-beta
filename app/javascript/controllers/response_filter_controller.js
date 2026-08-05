import { Controller } from "@hotwired/stimulus"

// Client-side response filter for the single-hujah page. No fetch, no re-render —
// it just shows/hides the already-rendered child cards by toggling the `hidden`
// attribute, and reflects the active tab via aria-pressed.
//
// Contract (data attributes wired in _response_filter.html.erb / _child_card.html.erb):
//   tabs:  data-response-filter-target="tab" + data-response-filter-filter-param="<filter>"
//   items: data-response-filter-target="item" + data-response-filter-vote="<stance>"
export default class extends Controller {
  static targets = ["tab", "item"]
  static values = { active: { type: String, default: "all" } }

  filter(event) {
    this.activeValue = event.params.filter
  }

  activeValueChanged(value) {
    this.itemTargets.forEach((el) => {
      const show = value === "all" || el.dataset.responseFilterVote === value
      el.toggleAttribute("hidden", !show)
    })
    this.tabTargets.forEach((tab) => {
      tab.setAttribute(
        "aria-pressed",
        String(tab.dataset.responseFilterFilterParam === value)
      )
    })
  }
}
