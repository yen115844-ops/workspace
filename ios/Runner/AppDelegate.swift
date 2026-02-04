import Flutter
import UIKit
import UserNotifications
import PushKit
import CallKit
import AVFoundation
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Setup VoIP PushKit
        let mainQueue = DispatchQueue.main
        let voipRegistry: PKPushRegistry = PKPushRegistry(queue: mainQueue)
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [PKPushType.voIP]
        
        // Setup notification delegate for missed call notification
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - PKPushRegistryDelegate
    
    /// Nhận VoIP token - GỬI TOKEN NÀY LÊN SERVER ĐỂ GỬI VoIP PUSH
    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
        print("[VoIP] Device Token: \(deviceToken)")
        
        // Lưu token cho Flutter sử dụng
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
    }
    
    /// Khi VoIP token bị invalidate
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("[VoIP] Token invalidated")
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
    }
    
    /// QUAN TRỌNG: Nhận VoIP push notification và hiển thị CallKit UI
    /// Phải gọi reportNewIncomingCall trong vòng vài giây, nếu không iOS sẽ crash app
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("[VoIP] Received push: \(payload.dictionaryPayload)")
        
        guard type == .voIP else {
            completion()
            return
        }
        
        // Parse data từ VoIP payload
        let payloadDict = payload.dictionaryPayload
        let id = payloadDict["id"] as? String ?? UUID().uuidString
        let nameCaller = payloadDict["callerName"] as? String ?? "Cuộc gọi đến"
        let handle = payloadDict["channelName"] as? String ?? "Voice Room"
        let isVideo = payloadDict["isVideo"] as? Bool ?? false
        
        // Tạo data cho CallKit
        let data = flutter_callkit_incoming.Data(id: id, nameCaller: nameCaller, handle: handle, type: isVideo ? 1 : 0)
        data.extra = [
            "channelId": payloadDict["channelId"] ?? "",
            "channelName": payloadDict["channelName"] ?? "",
            "callerId": payloadDict["callerId"] ?? "",
            "callerName": payloadDict["callerName"] ?? "",
            "workspaceId": payloadDict["workspaceId"] ?? ""
        ]
        data.appName = "WorkChat"
        data.iconName = "AppIcon"
        data.duration = 45000 // 45 giây timeout
        
        // iOS params
        data.handleType = "generic"
        data.supportsVideo = true
        data.supportsDTMF = true
        data.supportsHolding = true
        data.ringtonePath = "system_ringtone_default"
        
        // Hiển thị CallKit UI - BẮT BUỘC phải gọi trong pushRegistry
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
            completion()
        }
    }
    
    // MARK: - Handle Recent Call History Callback
    
    /// Xử lý khi user gọi lại từ Recent Call History
    override func application(_ application: UIApplication,
                              continue userActivity: NSUserActivity,
                              restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        
        guard let handleObj = userActivity.handle else {
            return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
        }
        
        guard let isVideo = userActivity.isVideo else {
            return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
        }
        
        let objData = handleObj.getDecryptHandle()
        let nameCaller = objData["nameCaller"] as? String ?? ""
        let handle = objData["handle"] as? String ?? ""
        let data = flutter_callkit_incoming.Data(id: UUID().uuidString, nameCaller: nameCaller, handle: handle, type: isVideo ? 1 : 0)
        
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.startCall(data, fromPushKit: true)
        
        return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
    
    // MARK: - UNUserNotificationCenterDelegate (Missed call notification)
    
    /// Hiển thị notification khi app ở foreground
    override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                         willPresent notification: UNNotification,
                                         withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Cho phép CallkitNotificationManager xử lý missed call notification
        CallkitNotificationManager.shared.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
    
    /// Xử lý khi user tap vào notification (ví dụ: Gọi lại từ missed call)
    override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                         didReceive response: UNNotificationResponse,
                                         withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == CallkitNotificationManager.CALLBACK_ACTION {
            let data = response.notification.request.content.userInfo as? [String: Any]
            SwiftFlutterCallkitIncomingPlugin.sharedInstance?.sendCallbackEvent(data)
        }
        completionHandler()
    }
    
    // MARK: - CallkitIncomingAppDelegate
    
    /// Khi user Accept cuộc gọi
    func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
        print("[CallKit] Call accepted: \(call.uuid)")
        // Fulfill action để CallKit biết đã xử lý xong
        action.fulfill()
    }
    
    /// Khi user Decline cuộc gọi
    func onDecline(_ call: Call, _ action: CXEndCallAction) {
        print("[CallKit] Call declined: \(call.uuid)")
        action.fulfill()
    }
    
    /// Khi cuộc gọi kết thúc
    func onEnd(_ call: Call, _ action: CXEndCallAction) {
        print("[CallKit] Call ended: \(call.uuid)")
        action.fulfill()
    }
    
    /// Khi cuộc gọi timeout (không trả lời)
    func onTimeOut(_ call: Call) {
        print("[CallKit] Call timeout: \(call.uuid)")
    }
    
    /// Audio session activated (cho WebRTC)
    func didActivateAudioSession(_ audioSession: AVAudioSession) {
        print("[CallKit] Audio session activated")
        // Nếu dùng WebRTC:
        // RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        // RTCAudioSession.sharedInstance().isAudioEnabled = true
    }
    
    /// Audio session deactivated
    func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
        print("[CallKit] Audio session deactivated")
        // Nếu dùng WebRTC:
        // RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        // RTCAudioSession.sharedInstance().isAudioEnabled = false
    }
}
