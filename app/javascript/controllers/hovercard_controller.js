import { Controller } from "@hotwired/stimulus"

// Slice B user hovercard. Attached to every `ui/_user_link` anchor (a genuine link to
// the profile). On a fine-pointer hover/focus it fetches the layout-less card body
// (users#card, `user_card_path`) and shows it in a single floating panel; a click just
// navigates the underlying anchor.
//
// The panel and the fetch cache are MODULE-SCOPED singletons shared by every instance:
// there is only ever ONE card element in the <body>, and a username's HTML is fetched
// at most once. Positioning is inline style (the panel is `fixed`); the visual chrome
// is Tailwind utilities safelisted in application.css because they are assembled here,
// not written literally in any scanned template.
//
// Touch/coarse-pointer clients get no card — the anchor click navigates instead. JS-off
// clients get the same, since the whole behaviour lives in this controller.
//
// teardown() is invoked by the one-time turbo:before-cache loop in application.js so a
// cached page snapshot never restores a stuck-open card; disconnect() clears this
// instance's timers and the document-level listeners it installed (no leaks).

const cache = new Map() // username → fetched HTML string
let panel = null // the single shared floating card element
let panelUsername = null // which username the panel currently shows
let hideTimer = null // shared hide timer (only one panel to hide)
let overPanel = false // pointer currently over the panel itself

const SHOW_DELAY = 400
const HIDE_DELAY = 200
const GUTTER = 8

function ensurePanel() {
  if (panel) return panel
  panel = document.createElement("div")
  panel.className =
    "bg-card shadow rounded fixed z-50 w-72 opacity-0 pointer-events-none " +
    "transition-opacity duration-150"
  // Keep-open bridge: moving the cursor trigger→card must not hide the card.
  panel.addEventListener("mouseenter", () => {
    overPanel = true
    clearTimeout(hideTimer)
  })
  panel.addEventListener("mouseleave", () => {
    overPanel = false
    hideTimer = setTimeout(hidePanel, HIDE_DELAY)
  })
  document.body.appendChild(panel)
  return panel
}

function showPanel() {
  const el = ensurePanel()
  el.classList.remove("opacity-0", "pointer-events-none")
  el.classList.add("opacity-100")
}

function hidePanel() {
  if (!panel) return
  panel.classList.remove("opacity-100")
  panel.classList.add("opacity-0", "pointer-events-none")
  panelUsername = null
}

export default class extends Controller {
  static values = { username: String, url: String }

  scheduleShow() {
    // Coarse pointer (touch): the link click just navigates, no card.
    if (window.matchMedia("(pointer: coarse)").matches) return

    clearTimeout(hideTimer)
    clearTimeout(this.showTimer)
    this.showTimer = setTimeout(() => this.show(), SHOW_DELAY)
  }

  scheduleHide() {
    clearTimeout(this.showTimer)
    clearTimeout(hideTimer)
    hideTimer = setTimeout(() => {
      // Do not hide while the pointer rests on the panel or this trigger.
      if (overPanel || this.hovering) return
      hidePanel()
    }, HIDE_DELAY)
  }

  async show() {
    const el = ensurePanel()
    const username = this.usernameValue

    if (cache.has(username)) {
      this.render(el, username, cache.get(username))
      return
    }

    const response = await fetch(this.urlValue, { headers: { Accept: "text/html" } })
    if (!response.ok) return
    const html = await response.text()
    cache.set(username, html)

    // A different trigger may have won the race while we were fetching; if the user is
    // no longer hovering this trigger, drop the stale result.
    if (!this.hovering) return
    this.render(el, username, html)
  }

  render(el, username, html) {
    el.innerHTML = html
    panelUsername = username
    this.position(el)
    showPanel()
  }

  // Position the fixed panel from the trigger's viewport rect: default below, flip
  // above on bottom overflow, clamp horizontally into the viewport.
  position(el) {
    const rect = this.element.getBoundingClientRect()
    // Measure with the panel laid out but before the fade so width/height are real.
    el.style.top = "0px"
    el.style.left = "0px"
    const { width, height } = el.getBoundingClientRect()

    let top = rect.bottom + GUTTER
    if (top + height > window.innerHeight - GUTTER) {
      const above = rect.top - GUTTER - height
      if (above >= GUTTER) top = above
    }

    let left = rect.left
    const maxLeft = window.innerWidth - width - GUTTER
    if (left > maxLeft) left = maxLeft
    if (left < GUTTER) left = GUTTER

    el.style.top = `${top}px`
    el.style.left = `${left}px`
  }

  // --- dismissal wiring -------------------------------------------------------

  connect() {
    this.hovering = false
    this.onMouseEnter = () => (this.hovering = true)
    this.onMouseLeave = () => (this.hovering = false)
    this.element.addEventListener("mouseenter", this.onMouseEnter)
    this.element.addEventListener("mouseleave", this.onMouseLeave)
    this.element.addEventListener("focusin", this.onMouseEnter)
    this.element.addEventListener("focusout", this.onMouseLeave)

    this.onScroll = () => hidePanel()
    this.onKeydown = (event) => {
      if (event.key === "Escape") hidePanel()
    }
    this.onDocClick = (event) => {
      if (this.element.contains(event.target)) return
      if (panel && panel.contains(event.target)) return
      hidePanel()
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("click", this.onDocClick)
  }

  teardown() {
    clearTimeout(this.showTimer)
    clearTimeout(hideTimer)
    hidePanel()
  }

  disconnect() {
    clearTimeout(this.showTimer)
    this.element.removeEventListener("mouseenter", this.onMouseEnter)
    this.element.removeEventListener("mouseleave", this.onMouseLeave)
    this.element.removeEventListener("focusin", this.onMouseEnter)
    this.element.removeEventListener("focusout", this.onMouseLeave)
    window.removeEventListener("scroll", this.onScroll)
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onDocClick)
  }
}
