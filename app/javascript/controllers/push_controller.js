import { Controller } from "@hotwired/stimulus"

// Registers for push notifications when running inside the Capacitor shell.
// Attach to the <body> tag: data-controller="push"
//
// The Capacitor bridge exposes window.Capacitor when the app runs in the native
// shell. On the web this controller is a no-op. iOS goes through APNs, Android
// through FCM (which requires google-services.json baked into the Android build,
// or register() crashes the native shell).
export default class extends Controller {
  connect() {
    if (!window.Capacitor?.isNativePlatform()) return

    const platform = window.Capacitor.getPlatform()
    if (platform !== "ios" && platform !== "android") return

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
      const platform = window.Capacitor.getPlatform() // "ios" | "android"
      await fetch("/api/v1/device_tokens", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token: token, platform: platform })
      })
      console.log("Device token registered with server")
    } catch (e) {
      console.error("Failed to register device token:", e)
    }
  }
}
