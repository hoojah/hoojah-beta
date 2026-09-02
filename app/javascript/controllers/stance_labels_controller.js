import { Controller } from "@hotwired/stimulus"

// Slice 3 — inline click-to-edit for the composer's three stance words on the
// "How people will weigh in" block. Tapping a word swaps it for a text input;
// committing (blur or Enter) writes the value into the adjacent hidden
// hujah[<stance>_label] field. Blank or equal-to-default submits empty, so the model
// normalises it back to nil. Rendered ONLY for eligible authors.
export default class extends Controller {
  static targets = ["word"]

  edit(event) {
    const word = event.currentTarget
    if (word.dataset.editing === "true") return
    word.dataset.editing = "true"

    const hidden = word.parentElement.querySelector("input[type=hidden]")
    const field = document.createElement("input")
    field.type = "text"
    field.maxLength = 24
    field.value = hidden.value || word.textContent.trim()
    field.className = word.className + " bg-transparent text-center w-full outline-none border-b border-current"
    field.setAttribute("aria-label", "Custom " + word.dataset.default + " label")

    word.replaceWith(field)
    field.focus()
    field.select()

    const commit = () => {
      const value = field.value.replace(/\s+/g, " ").trim().slice(0, 24)
      const isDefault = value === "" || value.toLowerCase() === word.dataset.default.toLowerCase()
      hidden.value = isDefault ? "" : value
      word.textContent = isDefault ? word.dataset.default : value
      word.dataset.editing = "false"
      field.replaceWith(word)
    }

    field.addEventListener("blur", commit)
    field.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); field.blur() }
      if (e.key === "Escape") { field.value = hidden.value; field.blur() }
    })
  }
}
