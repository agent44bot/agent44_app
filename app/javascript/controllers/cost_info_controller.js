import { Controller } from "@hotwired/stimulus"

// The (i) cost-info dialogs. Each card's $/mo badge has an (i) trigger; the
// dialogs themselves live outside the card links (invalid to nest a <dialog>
// in an <a>) and are opened by id. The card is a link, so opening must swallow
// the click (preventDefault + stopPropagation) or the card navigates away
// underneath the modal. Native <dialog>: ESC and a backdrop click also close.
export default class extends Controller {
  open(event) {
    event.preventDefault()
    event.stopPropagation()
    const dialog = document.getElementById(event.params.id)
    if (dialog) dialog.showModal()
  }

  close(event) {
    event.preventDefault()
    event.stopPropagation()
    event.target.closest("dialog")?.close()
  }

  backdropClose(event) {
    if (event.target.tagName === "DIALOG") event.target.close()
  }
}
