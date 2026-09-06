import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

const ALLOWED = ["image/png", "image/jpeg", "image/gif", "image/webp"]
const MAX_BYTES = 5 * 1024 * 1024

// Wires the composer's "Add image" flow: opens the dialog, validates the chosen file,
// direct-uploads it in the background, and writes the blob signed_id into the hidden
// hujah[image] field. Mounted on the composer form alongside the `composer` controller.
//
// Post-button coordination: `composer` gates Post on body length via its own sync().
// While an upload is in flight we force Post disabled; when it settles (success, cancel,
// or failure) we do NOT flip it back to enabled ourselves — we re-dispatch `input` on the
// composer body so composer#sync() re-derives the correct length-based state. That keeps
// the two controllers from fighting and never leaves Post stuck.
export default class extends Controller {
  static targets = [
    "dialog", "title", "chooser", "error", "errorTitle", "errorBody",
    "progress", "progressPreview", "progressName", "progressPct", "progressBar",
    "failed", "failedName", "fileInput", "cameraInput", "signedId",
    "attached", "attachedPreview", "attachedMeta", "triggerButton"
  ]
  static values = { directUrl: String }

  connect() {
    this.upload = null
    this.lastFile = null
    this.previewUrl = null
  }

  disconnect() { this.revokePreview() }

  openDialog() { this.resetToChooser(); this.dialogTarget.showModal() }
  closeDialog() { this.dialogTarget.close() }
  // Native <dialog> stretches to the viewport; a click whose target IS the dialog element
  // (not a child) landed on the backdrop.
  backdropClose(event) { if (event.target === this.dialogTarget) this.dialogTarget.close() }

  pickFile() { this.fileInputTarget.click() }
  pickCamera() { this.cameraInputTarget.click() }

  fileChosen(event) {
    const file = event.target.files[0]
    event.target.value = "" // allow re-choosing the same file after a cancel/error
    if (!file) return
    this.lastFile = file
    const err = this.validate(file)
    if (err) return this.showError(err.title, err.body)
    this.startUpload(file)
  }

  validate(file) {
    if (!ALLOWED.includes(file.type)) {
      const ext = (file.name.split(".").pop() || "file").toLowerCase()
      return { title: `We can't attach a .${ext} file.`, body: "Export it as JPG or PNG, then try again." }
    }
    if (file.size > MAX_BYTES) {
      const mb = (file.size / 1024 / 1024).toFixed(1)
      return { title: `That image is ${mb} MB — the limit is 5 MB.`, body: "Try a smaller one, or screenshot it first." }
    }
    return null
  }

  startUpload(file) {
    this.showProgress(file)
    this.revokePreview()
    this.previewUrl = URL.createObjectURL(file)
    this.progressPreviewTarget.src = this.previewUrl
    this.lockPost()

    this.upload = new DirectUpload(file, this.directUrlValue, {
      directUploadWillStoreFileWithXHR: (xhr) => {
        xhr.upload.addEventListener("progress", (e) => {
          if (!e.lengthComputable) return
          const pct = Math.round((e.loaded / e.total) * 100)
          this.progressPctTarget.textContent = `${pct}%`
          this.progressBarTarget.style.width = `${pct}%`
        })
      }
    })

    this.upload.create((error, blob) => {
      this.upload = null
      if (error) return this.showFailed(file)
      this.signedIdTarget.value = blob.signed_id
      this.showAttached(file)
      this.restoreGate()
      this.dialogTarget.close()
    })
  }

  cancelUpload() {
    // We can't truly abort an in-flight DirectUpload XHR here, but dropping the reference
    // and clearing the hidden field means its late success is ignored on submit.
    this.upload = null
    this.signedIdTarget.value = ""
    this.restoreGate()
    this.resetToChooser()
    this.dialogTarget.close()
  }

  retry() { if (this.lastFile) this.startUpload(this.lastFile) }

  remove() {
    this.signedIdTarget.value = ""
    this.attachedTarget.hidden = true
    this.attachedPreviewTarget.removeAttribute("src")
    this.revokePreview()
    this.triggerButtonTarget.classList.remove("bg-primary-soft", "text-primary")
    this.triggerButtonTarget.classList.add("bg-card-2", "text-ink-2")
  }

  // --- view state helpers ---
  resetToChooser() {
    this.errorTarget.hidden = true
    this.progressTarget.hidden = true
    this.failedTarget.hidden = true
    this.chooserTarget.hidden = false
    this.titleTarget.textContent = "Add an image"
  }
  showError(title, body) {
    this.resetToChooser()
    this.errorTitleTarget.textContent = title
    this.errorBodyTarget.textContent = body
    this.errorTarget.hidden = false
  }
  showProgress(file) {
    this.chooserTarget.hidden = true
    this.errorTarget.hidden = true
    this.failedTarget.hidden = true
    this.titleTarget.textContent = "Adding your image"
    this.progressNameTarget.textContent = `${file.name} · ${(file.size / 1024 / 1024).toFixed(1)} MB`
    this.progressPctTarget.textContent = "0%"
    this.progressBarTarget.style.width = "0%"
    this.progressTarget.hidden = false
  }
  showFailed(file) {
    this.restoreGate()
    this.progressTarget.hidden = true
    this.failedNameTarget.textContent = `${file.name} · ${(file.size / 1024 / 1024).toFixed(1)} MB · check your connection`
    this.failedTarget.hidden = false
  }
  showAttached(file) {
    this.attachedPreviewTarget.src = this.previewUrl
    this.attachedMetaTarget.textContent = `${(file.size / 1024 / 1024).toFixed(1)} MB · 16:9 crop`
    this.attachedTarget.hidden = false
    this.triggerButtonTarget.classList.remove("bg-card-2", "text-ink-2")
    this.triggerButtonTarget.classList.add("bg-primary-soft", "text-primary")
  }

  // --- Post-button coordination with the composer controller ---
  lockPost() {
    const post = this.postButton()
    if (post) post.disabled = true
  }
  // Hand gating back to the composer: re-run its length check rather than force-enabling.
  restoreGate() {
    const body = this.element.querySelector('[data-composer-target="body"]')
    if (body) {
      body.dispatchEvent(new Event("input", { bubbles: true }))
    } else {
      const post = this.postButton()
      if (post) post.disabled = false
    }
  }
  postButton() { return this.element.querySelector('[data-composer-target="post"]') }

  revokePreview() {
    if (this.previewUrl) { URL.revokeObjectURL(this.previewUrl); this.previewUrl = null }
  }
}
