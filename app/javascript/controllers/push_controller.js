import { Controller } from "@hotwired/stimulus"

// Registers for iOS push notifications when running inside the Capacitor shell.
// Attach to the <body> tag: data-controller="push"
//
// The Capacitor bridge exposes window.Capacitor when the app runs in the native
// shell. On the web this controller is a no-op.
export default class extends Controller {
  connect() {
    if (!window.Capacitor?.isNativePlatform()) return

    // iOS only for now. On Android, register() goes through FCM, and the build
    // ships without google-services.json (push deferred), so Firebase's default
    // app isn't initialized and register() crashes the native shell, a native
    // crash the try/catch below can't catch. Re-enable Android here once the
    // Agent44 Firebase project + google-services.json are in place.
    if (window.Capacitor.getPlatform() !== "ios") return

    this.registerPush()
  }

  async registerPush() {
    try {
      const PushNotifications = window.Capacitor.Plugins.PushNotifications
      if (!PushNotifications) {
        console.error("PushNotifications plugin not available")
        return
      }

      const permission = await PushNotifications.requestPermissions()
      if (permission.receive !== "granted") return

      await PushNotifications.addListener("registration", async (token) => {
        console.log("Push token received:", token.value.substring(0, 16) + "...")
        await this.sendTokenToServer(token.value)
      })

      await PushNotifications.addListener("registrationError", (error) => {
        console.error("Push registration failed:", error)
      })

      await PushNotifications.addListener("pushNotificationActionPerformed", (action) => {
        const url = action?.notification?.data?.url
        if (url) window.location.href = url
      })

      await PushNotifications.register()
    } catch (e) {
      console.error("Push setup error:", e)
    }
  }

  async sendTokenToServer(token) {
    try {
      await fetch("/api/v1/device_tokens", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token: token, platform: "ios" })
      })
      console.log("Device token registered with server")
    } catch (e) {
      console.error("Failed to register device token:", e)
    }
  }
}
