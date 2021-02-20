//
//  SDK iOS
//  SingleWave.swift
//
//  Created by Sergio Abril Herrero on 4/2/21.
//

import Foundation
import UIKit
import UserNotifications

public class SingleWave: NSObject, UNUserNotificationCenterDelegate, UIApplicationDelegate  {
    
    // MARK: Shared Singleton
    private static var instance: SingleWave?
    
    // MARK: Initializers
    public init(projectId: String, launchOptions: [UIApplication.LaunchOptionsKey: Any]?, debug: Bool = false) {
        // Super init
        super.init();
        // Save Instance
        SingleWave.instance = self;
        // Set debug
        self.debugMode = debug;
        // Log build
        if let text = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            print("[SingleWave] Initializing... build \(text)")
        }else{
            print("[SingleWave] Possible Error: Unknown build!")
        }
        // Log
        SingleWave.printLog(text: "The project id is \(projectId), launchOptions: \(String(describing: launchOptions)) and debug \(debug)")
        // Save projectId
        self.projectId = projectId
        // Set notification delegate to this, so we dont miss stuff?
        UNUserNotificationCenter.current().delegate = self
        UIApplication.shared.delegate = self;
        // Clean Badge for possible notifications
        UIApplication.shared.applicationIconBadgeNumber = 0
        // Get user custom data saved (if any)
        self.userCustomData = loadUserCustomData()
        SingleWave.printLog(text: "Saved user data (prev): \(self.userCustomData)")
        // Get user Device Token saved (if any)
        self.userDeviceToken = loadUserDeviceToken() ?? ""
        SingleWave.printLog(text: "Saved user token (prev): \(self.userDeviceToken)")
        // Check notification status, and register for remoteNotifications if authorized
        // Because sometimes APNS force a device to get a new token, and we need to catch it
        self.checkPermissions();
        // Ask for permissions
        SingleWave.promptPushPermissions();
        
        // SAVE DICC
        saveUserCustomData(dicc: ["hola": "nope"])
    }
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Vars
    private var debugMode: Bool = false
    private var projectId: String?
    private var userDeviceToken: String = ""
    private var userCustomData: [String : String] = [:]
    
    // MARK: Internal methods
    
    // Check for permissions, called on start, and if authorized, register for remote notifications to update the token (if APN ask us to do so)
    private func checkPermissions() -> Void
    {
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings(completionHandler: { permission in
            switch permission.authorizationStatus  {
                case .authorized:
                    SingleWave.printLog(text: "User granted permission for notification")
                    // Register again so I receive the token and can update it to the backend?
                    DispatchQueue.main.async {
                         UIApplication.shared.registerForRemoteNotifications()
                    }
                case .denied:
                    SingleWave.printLog(text: "User denied notification permission")
                case .notDetermined:
                    SingleWave.printLog(text: "Notification permission haven't been asked yet")
                case .provisional:
                    // @available(iOS 12.0, *)
                    SingleWave.printLog(text: "The application is authorized to post non-interruptive user notifications.")
                case .ephemeral:
                    // @available(iOS 14.0, *)
                    SingleWave.printLog(text: "The application is temporarily authorized to post notifications. Only available to app clips.")
                @unknown default:
                    SingleWave.printLog(text: "Unknow Status")
            }
        })
        
        return
    }
    
    // When this is called, the native alert is prompted to users so they accept
    private func promptPushPermissions()
    {
        SingleWave.printLog(text: "Requesting notifications permissions...")
        let current = UNUserNotificationCenter.current()
        current.requestAuthorization(options: [.alert, .sound, .badge], completionHandler: { granted, error in
            
            // TODO: handle error
            SingleWave.printLog(text: "Answered: Status is \(granted) and error is \(String(describing: error))")
            
            // Handle response
            if(granted)
            {
                SingleWave.printLog(text: "Status is true, send update to the server?")
            }else{
                SingleWave.printLog(text: "Status is false, unregister? maybe not")
            }
            
            // Register for remove push notifications ONCE they have accepted
            guard granted else { return }
            DispatchQueue.main.async {
                 UIApplication.shared.registerForRemoteNotifications()
            }
        })
    }
    
    // Called by AppDelegate extension when e get the token (needs to be public for that reason)
    public func receivedNewDeviceToken(token: String)
    {
        SingleWave.printLog(text: "received new token, upload to singlewave: \(token)")
        // Save to live var
        self.userDeviceToken = token;
        // Save to disk for next time
        self.saveUserDeviceToken(token: token)
        // Register on our backend
        self.registerUserOnSingleWave();
    }
    
    // Register on SingleWav
    public func registerUserOnSingleWave()
    {
        SingleWave.printLog(text: "Sending registration to SingleWave Backend...")
        
        // Build json string for customUserData (so we can parse it server side)
        var customDataJSONString = "{";
        for (keyDicc, valueDicc) in self.userCustomData {
            customDataJSONString += "\"\(keyDicc)\":\"\(valueDicc)\""
        }
        customDataJSONString += "}"
        
        let url = URL(string: "https://backend.singlewave.io/v1/subscribers/register")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "language", value: NSLocale.current.languageCode),
            URLQueryItem(name: "hash", value: self.projectId),
            URLQueryItem(name: "platform", value: "mobile-ios"),
            URLQueryItem(name: "token", value: self.userDeviceToken),
            URLQueryItem(name: "data", value: customDataJSONString)
        ]
        

        let query = components.url!.query
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(query!.utf8)
        
        //create dataTask using the session object to send data to the server
        let session = URLSession.shared
        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in

            guard error == nil else {
                return
            }

            guard let data = data else {
                return
            }

            do {
                //create json object from data
                if let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                    print(json)
                    // handle json...
                }
            } catch let error {
                print(error.localizedDescription)
            }
        })
        task.resume()
    }
    
    // Register Notification Open
    public func trackNotificationOpenSingleWave(notificationHash: String, openHash: String, controlHash: String)
    {
        SingleWave.printLog(text: "Sending track open to SingleWave Backend...")

        
        let url = URL(string: "https://backend.singlewave.io/v1/subscribers/open")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "platform", value: "mobile-ios"),
            URLQueryItem(name: "notificationHash", value: notificationHash),
            URLQueryItem(name: "openHash", value: openHash),
            URLQueryItem(name: "controlHash", value: controlHash),
        ]
        

        let query = components.url!.query
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(query!.utf8)
        
        //create dataTask using the session object to send data to the server
        let session = URLSession.shared
        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in

            guard error == nil else {
                return
            }

            guard let data = data else {
                return
            }

            do {
                //create json object from data
                if let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                    print(json)
                    // handle json...
                }
            } catch let error {
                print(error.localizedDescription)
            }
        })
        task.resume()
    }
    
    // MARK: Load / Save data
    
    private let swUserDataKey = "__swSDKUserData"
    public func saveUserCustomData(dicc: [String: String]) {
        let defaults = UserDefaults.standard
        defaults.set(dicc, forKey: swUserDataKey)
    }
    public func loadUserCustomData() -> [String: String] {
        var defDicc: [String: String] = [:]
        
        let defaults = UserDefaults.standard
        let savedString = defaults.value(forKey: swUserDataKey) as? [String:String]
        if(savedString != nil)
        {
            defDicc = savedString ?? [:]
        }else{
        }
        return defDicc
    }
    
    private let swDeviceTokenKey = "__swSDKDeviceToken"
    public func saveUserDeviceToken(token: String) {
        let defaults = UserDefaults.standard
        defaults.set(token, forKey: swDeviceTokenKey)
    }
    public func loadUserDeviceToken() -> String? {
        var deviceToken: String?
        
        let defaults = UserDefaults.standard
        let savedString = defaults.value(forKey: swDeviceTokenKey) as? String
        if(savedString != nil)
        {
            deviceToken = savedString!
        }
        
        return deviceToken
    }
    
    // MARK: External methods
    
    // Retrieve instance singleton
    public static func sharedInstance() -> SingleWave
    {
        return instance!;
    }
    
    // External call to display prompt alert to user
    public static func promptPushPermissions()
    {
        sharedInstance().promptPushPermissions()
    }
    
    // Set User Data
    public static func setUserCustomData(customData: [String: String])
    {
        // Set to live variable
        SingleWave.sharedInstance().userCustomData = customData;
        
        // Save to user defaults
        SingleWave.sharedInstance().saveUserCustomData(dicc: customData)
        
        // Update on server cause we added custom data
        SingleWave.sharedInstance().registerUserOnSingleWave();
    }
    
    // Log helper
    static func printLog(text: String, important: Bool = false)
    {
        if(!important && !SingleWave.sharedInstance().debugMode){
            return;
        }
                
        print("[Singlewave] "+text)
    }
    
    // MARK: AppDelegate Delegates
    // So we receive delegate calls for AppDelegate, like remotePushToken responses, etc
    
    // Device registration
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let deviceTokenString = deviceToken.hexString
        SingleWave.printLog(text: "[SingleWave] DD Registered for remote: \(deviceTokenString)")
        SingleWave.sharedInstance().receivedNewDeviceToken(token: deviceTokenString)
    }
    // Error getting token
    public func application(_ application: UIApplication,
      didFailToRegisterForRemoteNotificationsWithError error: Error) {
      SingleWave.printLog(text: "Failed to register for push: \(error)", important: true)
    }
    
    // MARK: Notification Delegates
    // So we receive delegate calls for handling notification opens, taps, etc
    
    // Notificaation helper: This is called when you open the notification and the App was not closed
    // Im running some tests, and looks like it's also called if the app had been killed...
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void){
        
        SingleWave.printLog(text: "Notification Center Open")
        // Clean Badge
        UIApplication.shared.applicationIconBadgeNumber = 0
        // Read notification
        let data = response.notification.request.content.userInfo
        // print("Data:",data)
        if let appData = data["data"] as? [String : String] {
            // print("App Data ",appData)
            if let notificationHash = appData["notificationHash"], let openHash = appData["openHash"], let controlHash = appData["controlHash"] {
                // We can send back to the tracking that the notification was clicked / open
                trackNotificationOpenSingleWave(notificationHash: notificationHash, openHash: openHash, controlHash: controlHash)
            }
        }
        
        completionHandler();
    }
    
    // This method will be called when app received push notifications in foreground
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        SingleWave.printLog(text: "Notification Received while foreground")
        // Clean Badge
        UIApplication.shared.applicationIconBadgeNumber = 0
        // Read notification
        let data = notification.request.content.userInfo
        // print("Details ",data)
        // Since the app was open, we send the open track. If they try to tap again, it's ok, cause the server wont count it twice the same hash
        if let appData = data["data"] as? [String : String] {
            // print("App Data ",appData)
            if let notificationHash = appData["notificationHash"], let openHash = appData["openHash"], let controlHash = appData["controlHash"] {
                // We can send back to the tracking that the notification was clicked / open
                trackNotificationOpenSingleWave(notificationHash: notificationHash, openHash: openHash, controlHash: controlHash)
            }
        }
        // Present it
        completionHandler([.banner, /*.list, .badge,*/ .sound]) //.banner shows but don't send to notification center, so we avoid user tapping it again. If we want to send it to the notif center as well, add .list
    }
}

// HELPER TO PARSE TOKEN
extension Data {
    var hexString: String {
        let hexString = map { String(format: "%02.2hhx", $0) }.joined()
        return hexString
    }
}
