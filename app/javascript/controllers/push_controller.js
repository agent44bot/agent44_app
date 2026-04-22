import { Controller } from "@hotwired/stimulus"

// Registers for iOS push notifications when running inside the Capacitor shell.
// Attach to the <body> tag: data-controller="push"
//
// The Capacitor bridge exposes window.Capacitor when the app runs in the native
// shell. On the web this controller is a no-op.
export default class extends Controller {
  connect() {
    if (!window.Capacitor?.isNativePlatform()) return

    this.registerPush()
  }

  async registerPush() {
    try {
      const { PushNotifications } = await import("https://esm.sh/@capacitor/push-notifications@8")

      const permission = await PushNotifications.requestPermissions()
      if (permission.receive !== "granted") return

      PushNotifications.addListener("registration", async (token) => {
        await this.sendTokenToServer(token.value)
      })

      PushNotifications.addListener("registrationError", (error) => {
        console.error("Push registration failed:", error)
      })

      await PushNotifications.register()
    } catch (e) {
      console.error("Push setup error:", e)
    }
  }

  async sendTokenToServer(token) {
    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

      await fetch("/api/v1/device_tokens", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ token: token, platform: "ios" })
      })
    } catch (e) {
      console.error("Failed to register device token:", e)
    }
  }
}
