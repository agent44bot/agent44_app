import { Controller } from "@hotwired/stimulus"

// Passkey (Face ID) ceremonies. `register` runs from Settings; `authenticate`
// from the sign-in screen. The server speaks base64url (webauthn-ruby); the
// browser WebAuthn API speaks ArrayBuffers — this controller converts between.
export default class extends Controller {
  static values = {
    createChallengeUrl: String,
    createUrl:          String,
    authChallengeUrl:   String,
    authUrl:            String
  }
  static targets = ["status"]

  get supported() {
    return !!(window.PublicKeyCredential && navigator.credentials)
  }

  connect() {
    if (!this.supported) this.element.hidden = true // no WebAuthn → hide the UI
  }

  async register(event) {
    event?.preventDefault()
    if (!this.supported) return this._status("Passkeys aren't supported on this device.", true)
    try {
      const options    = await this._postJson(this.createChallengeUrlValue, {})
      const credential = await navigator.credentials.create({ publicKey: this._decodeCreate(options) })
      const result     = await this._postJson(this.createUrlValue, this._encodeAttestation(credential))
      this._status(`✓ ${result.nickname || "Passkey"} added.`)
      window.location.reload()
    } catch (err) {
      if (err?.name === "NotAllowedError") return // user cancelled the prompt
      this._status(err.message || "Couldn't add passkey.", true)
    }
  }

  async authenticate(event) {
    event?.preventDefault()
    if (!this.supported) return this._status("Passkeys aren't supported here — use your email.", true)
    try {
      const options   = await this._postJson(this.authChallengeUrlValue, {})
      const assertion = await navigator.credentials.get({ publicKey: this._decodeGet(options) })
      const result    = await this._postJson(this.authUrlValue, this._encodeAssertion(assertion))
      window.location.href = result.redirect_to || "/"
    } catch (err) {
      if (err?.name === "NotAllowedError") return // user cancelled
      this._status(err.message || "Face ID sign-in failed — use your email instead.", true)
    }
  }

  // --- options: base64url string → ArrayBuffer ---
  _decodeCreate(o) {
    o.challenge = this._toBuf(o.challenge)
    o.user.id   = this._toBuf(o.user.id)
    if (o.excludeCredentials) o.excludeCredentials = o.excludeCredentials.map(c => ({ ...c, id: this._toBuf(c.id) }))
    return o
  }
  _decodeGet(o) {
    o.challenge = this._toBuf(o.challenge)
    if (o.allowCredentials) o.allowCredentials = o.allowCredentials.map(c => ({ ...c, id: this._toBuf(c.id) }))
    return o
  }

  // --- result: ArrayBuffer → base64url string ---
  _encodeAttestation(c) {
    return {
      id: c.id, type: c.type, rawId: this._toB64(c.rawId),
      response: {
        attestationObject: this._toB64(c.response.attestationObject),
        clientDataJSON:    this._toB64(c.response.clientDataJSON)
      },
      clientExtensionResults: c.getClientExtensionResults?.() || {}
    }
  }
  _encodeAssertion(c) {
    return {
      id: c.id, type: c.type, rawId: this._toB64(c.rawId),
      response: {
        authenticatorData: this._toB64(c.response.authenticatorData),
        clientDataJSON:    this._toB64(c.response.clientDataJSON),
        signature:         this._toB64(c.response.signature),
        userHandle:        c.response.userHandle ? this._toB64(c.response.userHandle) : null
      },
      clientExtensionResults: c.getClientExtensionResults?.() || {}
    }
  }

  _toBuf(s) {
    const b64 = (s + "=".repeat((4 - (s.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/")
    const bin = atob(b64)
    const out = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
    return out.buffer
  }
  _toB64(buf) {
    const bytes = new Uint8Array(buf)
    let bin = ""
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i])
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  }

  async _postJson(url, body) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const res  = await fetch(url, {
      method:  "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrf || "" },
      body:    JSON.stringify(body)
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
    return data
  }

  _status(msg, isError = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = msg
    this.statusTarget.classList.toggle("text-red-400", isError)
  }
}
