//
//  AppDelegate.swift
//  RRStructureScanner
//
//  Created by Christopher Worley on 12/16/17.
//  Copyright © 2017 Ruthless Research, LLC. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?


	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
		// Override point for customization after application launch.
		
		preventApplicationFromStartingInTheBackgroundWhenTheStructureSensorIsPlugged()
		
		let authStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
		
		if authStatus != .authorized {
			NSLog("Not authorized to use the camera!")
			AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { granted in
			})
		}
			
		return true
	}

	func applicationWillResignActive(_ application: UIApplication) {
		// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
		// Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
	}

	func applicationDidEnterBackground(_ application: UIApplication) {
		// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
		// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
		// Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
	}

	func applicationWillTerminate(_ application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
	}

	func preventApplicationFromStartingInTheBackgroundWhenTheStructureSensorIsPlugged() {
		// Sadly, iOS 9.2+ introduced unexpected behavior: every time a Structure Sensor is plugged in to iOS, iOS will launch all Structure-related apps in the background.
		// The apps will not be visible to the user.
		// This can cause problems since Structure SDK apps typically ask the user for permission to use the camera when launched.
		// This leads to the user's first experience with a Structure SDK app being:
		//     1.  Download Structure SDK apps from App Store.
		//     2.  Plug in Structure Sensor to iPad.
		//     3.  Get bombarded with "X app wants to use the Camera" notifications from every installed Structure SDK app.
		// Each app has to deal with this problem in its own way.
		// In the Structure SDK, sample apps peacefully exit without causing a crash report.
		// This also has other benefits, such as not using memory.
		// Note that Structure SDK does not support connecting to Structure Sensor if the app is in the background.
		
		if UIApplication.shared.applicationState == .background {
			let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName")
			print("iOS launched \(String(describing: displayName)) in the background. This app is not designed to be launched in the background, so it will exit peacefully.")
			
			exit(0)
		}
	}

}

