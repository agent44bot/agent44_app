import UIKit
import WebKit
import LocalAuthentication
import UserNotifications
import Capacitor

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    private var blurView: UIVisualEffectView?
    private var needsAuth = true

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Show push notification banners even when the app is in the foreground
        UNUserNotificationCenter.current().delegate = self

        // Disable horizontal scroll on WKWebView once the view hierarchy is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.disableHorizontalScroll()
        }
        return true
    }

    // Show banner + sound even when app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.applicationIconBadgeNumber = 0
        if needsAuth {
            authenticate()
        } else {
            removeBlur()
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        showBlur()
        needsAuth = true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}

    // MARK: - Push Notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(
            name: .capacitorDidRegisterForRemoteNotifications,
            object: deviceToken
        )
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(
            name: .capacitorDidFailToRegisterForRemoteNotifications,
            object: error
        )
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    // MARK: - Disable Horizontal Scroll

    private func disableHorizontalScroll() {
        guard let rootVC = window?.rootViewController else { return }
        // Find the WKWebView's scroll view in the Capacitor bridge VC
        if let webView = findWebView(in: rootVC.view) {
            webView.scrollView.alwaysBounceHorizontal = false
            webView.scrollView.isDirectionalLockEnabled = true
        }
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let wk = view as? WKWebView { return wk }
        for sub in view.subviews {
            if let wk = findWebView(in: sub) { return wk }
        }
        return nil
    }

    // MARK: - Biometric Lock

    private func authenticate() {
        showBlur()

        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics or passcode configured — let them in
            needsAuth = false
            removeBlur()
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Agent44") { success, _ in
            DispatchQueue.main.async {
                if success {
                    self.needsAuth = false
                    self.removeBlur()
                } else {
                    // Stay locked — they can retry by backgrounding and foregrounding
                }
            }
        }
    }

    private func showBlur() {
        guard blurView == nil, let w = window else { return }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = w.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        w.addSubview(blur)
        blurView = blur
    }

    private func removeBlur() {
        UIView.animate(withDuration: 0.25) {
            self.blurView?.alpha = 0
        } completion: { _ in
            self.blurView?.removeFromSuperview()
            self.blurView = nil
        }
    }
}
