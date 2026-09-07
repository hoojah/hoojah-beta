import { Controller } from "@hotwired/stimulus"

// Full-screen image viewer opened from a hujah image (the :shown branch of
// hujahs/_hujah_image wires the click). Natural aspect (`object-contain`), an
// `@user · date` byline header, the alt text as a caption, and a
// "Pinch to zoom · swipe down to close" hint. Closes on backdrop click, Esc
// (native <dialog>), or a swipe-down gesture.
//
// The dialog is a native <dialog> shown with showModal(): that buys a focus
// trap, Esc-to-close, and top-layer stacking for free. It is built lazily on the
// first open and reused on subsequent opens; teardown() tears it down before
// Turbo snapshots the page so a restored page never comes back with a stuck-open
// full-screen modal.
export default class extends Controller {
  static values = { src: String, alt: String, byline: String }

  open(event) {
    // preventDefault: the shown image sits inside a card whose body is (today)
    // un-linked, but stopPropagation guards against any future surrounding <a>/
    // Turbo navigation swallowing the same click — the tap must open the viewer,
    // never navigate.
    event.preventDefault()
    event.stopPropagation()
    if (!this.dialog) this.build()
    this.dialog.showModal()
  }

  build() {
    const d = document.createElement("dialog")
    d.setAttribute("data-lightbox-target", "root")
    d.className = "p-0 m-0 w-screen h-screen max-w-none max-h-none bg-black/90 backdrop:bg-black/90"
    // innerHTML is the ONE place this controller writes markup from values, and
    // every interpolated value below is user-influenced (src/alt/byline). Each is
    // passed through escape() — DO NOT interpolate any of them raw.
    d.innerHTML = `
      <div class="w-full h-full flex flex-col text-white" data-role="wrap">
        <div class="flex items-center justify-between px-4 py-3 text-sm">
          <span>${this.escape(this.bylineValue)}</span>
          <button type="button" data-role="close" aria-label="Close" class="p-1 bg-transparent border-0 text-white cursor-pointer">✕</button>
        </div>
        <div class="flex-1 flex items-center justify-center overflow-auto px-4">
          <img src="${this.escape(this.srcValue)}" alt="${this.escape(this.altValue)}" class="max-w-full max-h-full object-contain">
        </div>
        <div class="px-4 py-3 text-center text-xs text-white/70">
          ${this.altValue ? `<div class="mb-1 text-white/90">${this.escape(this.altValue)}</div>` : ""}
          Pinch to zoom · swipe down to close
        </div>
      </div>`
    d.querySelector('[data-role="close"]').addEventListener("click", () => d.close())
    d.addEventListener("click", (e) => { if (e.target === d) d.close() })
    this.bindSwipeDown(d)
    document.body.appendChild(d)
    this.dialog = d
  }

  bindSwipeDown(d) {
    let startY = null
    const wrap = d.querySelector('[data-role="wrap"]')
    wrap.addEventListener("touchstart", (e) => { startY = e.touches[0].clientY }, { passive: true })
    wrap.addEventListener("touchend", (e) => {
      if (startY !== null && e.changedTouches[0].clientY - startY > 80) d.close()
      startY = null
    }, { passive: true })
  }

  escape(s) {
    return String(s || "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }

  teardown() {
    if (this.dialog) {
      if (this.dialog.open) this.dialog.close()
      this.dialog.remove()
      this.dialog = null
    }
  }
}
