import { Controller } from "@hotwired/stimulus"

// Storage-room scan console, shared by Receive (direction "in", cases) and
// Remove (direction "out", bottles). Three ways to identify an item:
//   • camera — html5-qrcode, lazy-loaded as a classic script only when the
//     camera is started. Works in iOS WebKit (which lacks the native
//     BarcodeDetector API); on Chrome/Android it uses BarcodeDetector under the
//     hood via experimentalFeatures.useBarCodeDetectorIfSupported.
//   • typing / pasting a code, or a USB/Bluetooth scanner (types + Enter)
//   • name search, for bottles that won't scan
// Confirming a quantity POSTs an InventoryMovement and logs it for the session.
export default class extends Controller {
  static values = {
    direction:    String,
    allowCreate:  Boolean,
    lookupUrl:    String,
    movementsUrl: String,
    libUrl:       String, // asset path to html5-qrcode.js
  }
  static targets = [
    "cameraWrap", "cameraUnsupported", "reader", "status", "cameraBtn",
    "codeInput", "searchInput", "results",
    "panel", "itemName", "itemMeta", "onHand", "qty", "confirmBtn",
    "newPanel", "newCode", "newName", "newCategory", "newUnits",
    "recent", "recentEmpty",
  ]

  connect() {
    this.current = null      // { item } once resolved, or { code } for a new barcode
    this.results = []
    this.scanning = false
    // Show the camera scanner only where it can actually run. In mobile Safari /
    // desktop the browser owns the camera permission, so any browser with
    // getUserMedia gets it. Inside the native app it's gated on a user-agent
    // token that only builds carrying NSCameraUsageDescription set on the
    // webview (capacitor.config ios.appendUserAgent) — older builds lack the
    // Info.plist string and iOS CRASHES the app if getUserMedia runs without it,
    // so they fall back to the type-a-code path instead.
    const hasApi   = !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)
    const isNative = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform())
    const cameraOk = hasApi && (!isNative || navigator.userAgent.includes("Agent44Cam"))
    ;(cameraOk ? this.cameraWrapTarget : this.cameraUnsupportedTarget).classList.remove("hidden")
  }

  disconnect() { this.stopCamera() }

  // ── Camera ──────────────────────────────────────────────────────────────
  toggleCamera() { this.scanning ? this.stopCamera() : this.startCamera() }

  // Lazy-load html5-qrcode (a classic script that sets window.__Html5QrcodeLibrary__)
  // the first time the camera is used, so it never weighs down a normal page load.
  loadLib() {
    if (window.__Html5QrcodeLibrary__) return Promise.resolve()
    if (this._libPromise) return this._libPromise
    this._libPromise = new Promise((resolve, reject) => {
      const s = document.createElement("script")
      s.src = this.libUrlValue
      s.onload = () => resolve()
      s.onerror = () => { this._libPromise = null; reject(new Error("load failed")) }
      document.head.appendChild(s)
    })
    return this._libPromise
  }

  async startCamera() {
    this.statusTarget.textContent = "Starting camera…"
    try {
      await this.loadLib()
    } catch {
      this.statusTarget.textContent = "Couldn't load the scanner. Type the code instead."
      return
    }
    const lib = window.__Html5QrcodeLibrary__
    const F = lib.Html5QrcodeSupportedFormats
    this.scanner = new lib.Html5Qrcode(this.readerTarget.id, {
      formatsToSupport: [
        F.EAN_13, F.EAN_8, F.UPC_A, F.UPC_E, F.UPC_EAN_EXTENSION,
        F.CODE_128, F.CODE_39, F.QR_CODE,
      ],
      experimentalFeatures: { useBarCodeDetectorIfSupported: true },
      verbose: false,
    })
    try {
      await this.scanner.start(
        { facingMode: "environment" },
        { fps: 10, qrbox: { width: 280, height: 170 } },
        (text) => this.onDetected(text),
        () => {} // per-frame "no code found" — ignore
      )
      this.scanning = true
      this.cameraBtnTarget.textContent = "Stop camera"
      this.statusTarget.textContent = "Point at a barcode…"
    } catch {
      this.statusTarget.textContent = "Camera unavailable. Allow camera access, or type the code."
      this.scanner = null
    }
  }

  async stopCamera() {
    this.scanning = false
    if (this.hasCameraBtnTarget) this.cameraBtnTarget.textContent = "Start camera"
    if (this.hasStatusTarget && !this.current) this.statusTarget.textContent = ""
    if (this.scanner) {
      try { await this.scanner.stop(); this.scanner.clear() } catch { /* already stopped */ }
      this.scanner = null
    }
  }

  onDetected(code) {
    if (this.current) return                         // a confirm panel is open
    const now = Date.now()
    if (code === this.lastCode && now - (this.lastCodeAt || 0) < 2500) return  // debounce
    this.lastCode = code; this.lastCodeAt = now
    if (navigator.vibrate) navigator.vibrate(40)
    this.lookupCode(code)
  }

  // ── Lookup ──────────────────────────────────────────────────────────────
  manualLookup(event) {
    if (event) event.preventDefault()
    const code = this.codeInputTarget.value.trim()
    if (!code) return
    this.codeInputTarget.value = ""
    this.lookupCode(code)
  }

  async lookupCode(code) {
    const data = await this.getJSON(`${this.lookupUrlValue}?code=${encodeURIComponent(code)}`)
    if (data.found) this.showItem(data.item)
    else this.showNew(code)
  }

  search() {
    clearTimeout(this._searchTimer)
    const q = this.searchInputTarget.value.trim()
    if (q.length < 2) { this.resultsTarget.classList.add("hidden"); return }
    this._searchTimer = setTimeout(async () => {
      const data = await this.getJSON(`${this.lookupUrlValue}?q=${encodeURIComponent(q)}`)
      this.results = data.results || []
      this.renderResults()
    }, 200)
  }

  renderResults() {
    if (!this.results.length) {
      this.resultsTarget.innerHTML = `<div class="px-3 py-2 text-sm text-gray-500 bg-gray-900">No matches.</div>`
    } else {
      this.resultsTarget.innerHTML = this.results.map((it, i) => `
        <button type="button" data-action="inventory-scanner#pickResult" data-index="${i}"
                class="block w-full text-left px-3 py-2 bg-gray-900 hover:bg-gray-800 text-sm">
          <span class="text-white">${this.esc(it.name)}</span>
          <span class="text-gray-500"> · ${it.on_hand} on hand</span>
        </button>`).join("")
    }
    this.resultsTarget.classList.remove("hidden")
  }

  pickResult(event) {
    const it = this.results[Number(event.currentTarget.dataset.index)]
    if (!it) return
    this.searchInputTarget.value = ""
    this.resultsTarget.classList.add("hidden")
    this.showItem(it)
  }

  // ── Confirm quantity ──────────────────────────────────────────────────────
  showItem(item) {
    this.current = { item }
    this.itemNameTarget.textContent = item.name
    this.itemMetaTarget.textContent = [item.category, item.size, item.producer].filter(Boolean).join(" · ")
    this.onHandTarget.textContent = item.on_hand
    this.qtyTarget.value = this.directionValue === "in" ? (item.default_in || 1) : 1
    this.hideNew()
    this.panelTarget.classList.remove("hidden")
  }

  inc() { this.qtyTarget.value = Math.max(1, (parseInt(this.qtyTarget.value, 10) || 0) + 1) }
  dec() { this.qtyTarget.value = Math.max(1, (parseInt(this.qtyTarget.value, 10) || 2) - 1) }

  cancel() { this.current = null; this.panelTarget.classList.add("hidden") }

  async confirm() {
    if (!this.current || !this.current.item) return
    const qty = Math.max(1, parseInt(this.qtyTarget.value, 10) || 1)
    const body = new FormData()
    body.append("item_id", this.current.item.id)
    body.append("direction", this.directionValue)
    body.append("quantity", qty)
    this.confirmButtonGuard(true)
    const { ok, json } = await this.postJSON(this.movementsUrlValue, body)
    this.confirmButtonGuard(false)
    if (ok && json.ok) {
      this.logMovement(json.item, json.movement)
      this.cancel()
    } else {
      this.statusMessage((json.errors || ["Couldn't record that."]).join(", "))
    }
  }

  // ── New barcode (receive only) ───────────────────────────────────────────
  showNew(code) {
    this.current = { code }
    this.panelTarget.classList.add("hidden")
    this.newCodeTarget.textContent = code
    this.newPanelTarget.classList.remove("hidden")
  }

  hideNew() { if (this.hasNewPanelTarget) this.newPanelTarget.classList.add("hidden") }

  async createAndReceive() {
    if (!this.allowCreateValue || !this.current || !this.current.code) return
    const name = this.newNameTarget.value.trim()
    if (!name) { this.newNameTarget.focus(); return }
    const kind  = this.element.querySelector('input[name="newkind"]:checked')?.value || "case"
    const units = Math.max(1, parseInt(this.newUnitsTarget.value, 10) || 12)
    const code  = this.current.code

    const body = new FormData()
    body.append("direction", "in")
    body.append("code", code)
    body.append("item[name]", name)
    body.append("item[category]", this.newCategoryTarget.value)
    body.append("item[units_per_case]", units)
    body.append(kind === "case" ? "item[case_barcode]" : "item[barcode]", code)
    body.append("quantity", kind === "case" ? units : 1)

    const { ok, json } = await this.postJSON(this.movementsUrlValue, body)
    if (ok && json.ok) {
      this.newNameTarget.value = ""
      this.hideNew()
      this.current = null
      this.logMovement(json.item, json.movement)
    } else {
      this.statusMessage((json.errors || ["Couldn't add that item."]).join(", "))
    }
  }

  // ── Session log ───────────────────────────────────────────────────────────
  logMovement(item, movement) {
    if (this.hasRecentEmptyTarget) this.recentEmptyTarget.classList.add("hidden")
    const inbound = movement.direction === "in"
    const row = document.createElement("div")
    row.className = "flex items-center gap-2 text-sm rounded-lg bg-gray-900 border border-gray-800 px-3 py-2"
    row.innerHTML = `
      <span class="${inbound ? "text-green-400" : "text-red-400"} font-bold tabular-nums w-10">
        ${inbound ? "+" : "−"}${movement.quantity}</span>
      <span class="text-gray-200 flex-1 min-w-0 truncate">${this.esc(item.name)}</span>
      <span class="text-gray-500 shrink-0 text-xs">${item.on_hand} on hand</span>`
    this.recentTarget.prepend(row)
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  confirmButtonGuard(busy) {
    if (!this.hasConfirmBtnTarget) return
    this.confirmBtnTarget.disabled = busy
    this.confirmBtnTarget.classList.toggle("opacity-50", busy)
  }

  statusMessage(msg) { if (this.hasStatusTarget) this.statusTarget.textContent = msg }

  csrf() { return document.querySelector('meta[name="csrf-token"]')?.content || "" }

  async getJSON(url) {
    const r = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
    return r.json()
  }

  async postJSON(url, body) {
    const r = await fetch(url, {
      method: "POST",
      headers: { Accept: "application/json", "X-CSRF-Token": this.csrf() },
      credentials: "same-origin",
      body,
    })
    const json = await r.json().catch(() => ({}))
    return { ok: r.ok, json }
  }

  esc(s) {
    const d = document.createElement("div")
    d.textContent = s == null ? "" : String(s)
    return d.innerHTML
  }
}
