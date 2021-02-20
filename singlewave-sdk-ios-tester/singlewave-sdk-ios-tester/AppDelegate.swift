//
//  AppDelegate.swift
//  singlewave-sdk-ios-tester
//
//  Created by Sergio Abril Herrero on 5/2/21.
//

import UIKit

import SingleWave

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    let testProjectId = "YOUR_PROJECT_ID"
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?) -> Bool {
        
        // print("Your code here")
        
        // Init Singlewave
        SingleWave.init(projectId: testProjectId, launchOptions: launchOptions, debug: true);

        return true
    }
}

