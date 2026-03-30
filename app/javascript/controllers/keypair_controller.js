import { Controller } from "@hotwired/stimulus"
import { schnorr } from "@noble/curves/secp256k1"
import { bytesToHex, hexToBytes } from "@noble/hashes/utils"
import { bech32 } from "@scure/base"

export default class extends Controller {
  static targets = [
    "generatePanel", "existingPanel",
    "keypairDisplay", "npubField", "nsecField",
    "nsecInput", "derivedDisplay", "derivedNpub"
  ]

  showGenerate() {
    this.generatePanelTarget.style.display = ""
    this.existingPanelTarget.style.display = "none"
    this.#updateTabActive(0)
  }

  showExisting() {
    this.generatePanelTarget.style.display = "none"
    this.existingPanelTarget.style.display = ""
    this.#updateTabActive(1)
  }

  generate() {
    const secretKey = schnorr.utils.randomPrivateKey()
    const pubkeyBytes = schnorr.getPublicKey(secretKey)

    const secretHex = bytesToHex(secretKey)
    const pubkeyHex = bytesToHex(pubkeyBytes)

    const nsec = this.#encodeBech32("nsec", secretHex)
    const npub = this.#encodeBech32("npub", pubkeyHex)

    this.npubFieldTarget.value = npub
    this.nsecFieldTarget.value = nsec
    this.keypairDisplayTarget.style.display = ""

    this.#setAuthFields(pubkeyHex, secretHex)
  }

  deriveAndSignIn() {
    this.deriveFromNsec()
    const authController = this.application.getControllerForElementAndIdentifier(this.element, "auth")
    if (authController) authController.signIn()
  }

  deriveFromNsecAfterPaste() {
    setTimeout(() => this.deriveFromNsec(), 0)
  }

  deriveFromNsec() {
    const input = this.nsecInputTarget.value.trim()
    if (!input) {
      if (this.hasDerivedDisplayTarget) this.derivedDisplayTarget.style.display = "none"
      return
    }

    try {
      let secretHex
      if (input.startsWith("nsec1")) {
        secretHex = this.#decodeBech32(input)
      } else if (/^[0-9a-f]{64}$/i.test(input)) {
        secretHex = input.toLowerCase()
      } else {
        if (this.hasDerivedDisplayTarget) this.derivedDisplayTarget.style.display = "none"
        return
      }

      const secretKey = hexToBytes(secretHex)
      const pubkeyBytes = schnorr.getPublicKey(secretKey)
      const pubkeyHex = bytesToHex(pubkeyBytes)
      const npub = this.#encodeBech32("npub", pubkeyHex)

      if (this.hasDerivedNpubTarget) this.derivedNpubTarget.value = npub
      if (this.hasDerivedDisplayTarget) this.derivedDisplayTarget.style.display = ""
      this.#setAuthFields(pubkeyHex, secretHex)
    } catch (e) {
      if (this.hasDerivedDisplayTarget) this.derivedDisplayTarget.style.display = "none"
    }
  }

  #encodeBech32(prefix, hexStr) {
    const data = hexToBytes(hexStr)
    const words = bech32.toWords(data)
    return bech32.encode(prefix, words, 1500)
  }

  #decodeBech32(bech32Str) {
    const { words } = bech32.decode(bech32Str, 1500)
    const data = bech32.fromWords(words)
    return bytesToHex(new Uint8Array(data))
  }

  #setAuthFields(pubkeyHex, secretHex) {
    const pubField = document.querySelector("[data-auth-target='pubkeyHex']")
    const secField = document.querySelector("[data-auth-target='secretKey']")
    if (pubField) pubField.value = pubkeyHex
    if (secField) secField.value = secretHex
  }

  #updateTabActive(index) {
    const tabs = this.element.querySelectorAll("[data-tab]")
    tabs.forEach((t, i) => t.classList.toggle("bg-orange-600", i === index))
    tabs.forEach((t, i) => t.classList.toggle("text-white", i === index))
    tabs.forEach((t, i) => t.classList.toggle("bg-gray-200", i !== index))
    tabs.forEach((t, i) => t.classList.toggle("text-gray-700", i !== index))
  }
}
