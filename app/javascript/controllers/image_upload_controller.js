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
//
// Cancellation is real, not cosmetic. Two mechanisms work together because DirectUpload's
// completion callback fires regardless of any UI state:
//   1. a generation token (uploadGen) — startUpload captures the current value; the create
//      callback bails immediately if the token moved (cancel/remove/supersede bump it), so
//      a late completion can never re-write signedId, reveal the attached state, or reopen
//      the gate for an upload the user already abandoned; and
//   2. XHR abort — the store XHR is captured and .abort()ed on cancel, so the bytes stop
//      going out and the (swallowed) aborted-error callback returns early on the token.
export default class extends Controller {
  static targets = [
    "dialog", "title", "chooser", "error", "errorTitle", "errorBody",
    "progress", "progressPreview", "progressName", "progressPct", "progressBar",
    "failed", "failedName", "fileInput", "cameraInput", "signedId",
    "attached", "attachedPreview", "attachedMeta", "triggerButton", "altInput"
  ]
  static values = { directUrl: String }

  connect() {
    this.upload = null
    this.xhr = null
    this.lastFile = null
    this.previewUrl = null
    this.uploadGen = 0
    this.uploading = false
  }

  disconnect() { this.revokePreview() }

  // application.js calls c.teardown?.() on turbo:before-cache; a snapshotted-open <dialog>
  // would restore stuck open, so close it (mirrors dialog_controller).
  teardown() { if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close() }

  openDialog() { this.resetToChooser(); this.dialogTarget.showModal() }
  // A backdrop click on a native <dialog> lands on the dialog element itself. Route it
  // through cancelUpload so an in-flight upload is aborted, not merely hidden.
  backdropClose(event) { if (event.target === this.dialogTarget) this.cancelUpload() }

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
    const gen = ++this.uploadGen // invalidates any previous in-flight callback
    this.uploading = true
    this.showProgress(file)
    this.revokePreview()
    this.previewUrl = URL.createObjectURL(file)
    this.progressPreviewTarget.src = this.previewUrl
    this.lockPost()

    this.upload = new DirectUpload(file, this.directUrlValue, {
      directUploadWillCreateBlobWithXHR: (xhr) => { this.xhr = xhr },
      directUploadWillStoreFileWithXHR: (xhr) => {
        this.xhr = xhr
        xhr.upload.addEventListener("progress", (e) => {
          if (!e.lengthComputable) return
          const pct = Math.round((e.loaded / e.total) * 100)
          this.progressPctTarget.textContent = `${pct}%`
          this.progressBarTarget.style.width = `${pct}%`
        })
      }
    })

    this.upload.create((error, blob) => {
      if (gen !== this.uploadGen) return // cancelled/superseded — ignore this completion
      this.upload = null
      this.xhr = null
      this.uploading = false
      if (error) return this.showFailed(file)
      this.signedIdTarget.value = blob.signed_id
      this.showAttached(file)
      this.restoreGate()
      this.dialogTarget.close()
    })
  }

  // Aborts an in-flight upload (bytes stop; token bump swallows its late callback) and
  // clears the field so nothing half-uploaded rides the POST. With no upload running this
  // is just a safe close — it must NOT wipe an already-attached image (Esc/backdrop after
  // a successful attach both land here).
  cancelUpload() {
    if (this.uploading) {
      this.uploadGen++
      if (this.xhr) { try { this.xhr.abort() } catch (_) { /* already settled */ } this.xhr = null }
      this.upload = null
      this.uploading = false
      this.signedIdTarget.value = ""
      this.restoreGate()
    }
    this.resetToChooser()
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  retry() { if (this.lastFile) this.startUpload(this.lastFile) }

  remove() {
    this.uploadGen++ // any in-flight completion for a removed image is now ignored
    this.uploading = false
    this.signedIdTarget.value = ""
    if (this.hasAltInputTarget) this.altInputTarget.value = "" // don't submit stale alt with no image
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
    this.titleTarget.textContent = "Add an image" // leave the "Adding your image" state
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
