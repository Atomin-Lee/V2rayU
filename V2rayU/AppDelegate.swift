//
//  AppDelegate.swift
//  V2rayU
//
//  Created by yanue on 2018/10/9.
//  Copyright © 2018 yanue. All rights reserved.
//

import Cocoa
import ServiceManagement
import Swifter

let launcherAppIdentifier = "net.yanue.V2rayU.Launcher"
let appVersion = getAppVersion()

let NOTIFY_TOGGLE_RUNNING_SHORTCUT = Notification.Name(rawValue: "NOTIFY_TOGGLE_RUNNING_SHORTCUT")
let NOTIFY_SWITCH_PROXY_MODE_SHORTCUT = Notification.Name(rawValue: "NOTIFY_SWITCH_PROXY_MODE_SHORTCUT")

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    // bar menu
    @IBOutlet weak var statusMenu: NSMenu!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // default settings
        self.checkDefault()

        // auto launch
        if UserDefaults.getBool(forKey: .autoLaunch) {
            // Insert code here to initialize your application
            let startedAtLogin = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == launcherAppIdentifier
            }

            if startedAtLogin {
                DistributedNotificationCenter.default().post(name: Notification.Name("terminateV2rayU"), object: Bundle.main.bundleIdentifier!)
            }
        }

        // check v2ray core
//        V2rayCore().check()
        // generate plist
        V2rayLaunch.generateLaunchAgentPlist()
        // auto check updates
        if UserDefaults.getBool(forKey: .autoCheckVersion) {
            // check version
            V2rayUpdater.checkForUpdatesInBackground()
        }

        _ = GeneratePACFile(rewrite: true)
        // start http server for pac
        V2rayLaunch.startHttpServer()

        // wake and sleep
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onSleepNote(note:)), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onWakeNote(note:)), name: NSWorkspace.didWakeNotification, object: nil)
        // url scheme
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(self.handleAppleEvent(event:replyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

        let path = Bundle.main.bundlePath
        // /Users/yanue/Library/Developer/Xcode/DerivedData/V2rayU-cqwhqdwsnxsplqgolfwfywalmjps/Build/Products/Debug
        // working dir must be: /Applications/V2rayU.app
        NSLog(String.init(format: "working dir:%@", path))

        if !(path.contains("Developer/Xcode") || path.contains("/Applications/V2rayU.app")) {
            makeToast(message: "Please drag 'V2rayU' to '/Applications' directory", displayDuration: 5.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                NSApplication.shared.terminate(self)
            }
        }

        // set global hotkey
        let notifyCenter = NotificationCenter.default
        notifyCenter.addObserver(forName: NOTIFY_TOGGLE_RUNNING_SHORTCUT, object: nil, queue: nil, using: {
            notice in
            ToggleRunning()
        })

        notifyCenter.addObserver(forName: NOTIFY_SWITCH_PROXY_MODE_SHORTCUT, object: nil, queue: nil, using: {
            notice in
            SwitchProxyMode()
        })

        // Register global hotkey
        ShortcutsController.bindShortcuts()
        
        // 更新freev2配置的入口
        /*let timeDate = Date.init(timeIntervalSinceNow: 79)
        let timer = Timer.init(fire: timeDate,interval: 60,repeats: true){(kTimer) in
            let now = Date()
            
            let dformatter = DateFormatter()
            dformatter.dateFormat = "ss"
            let seconds = dformatter.string(from: now)
            if(seconds != "00") {
                
                print("not now", to:&self.logger)
                return
            }
            
            print("开始更新freev2配置信息", to: &self.logger)
            self.getFreeV2()
        }
        RunLoop.current.add(timer, forMode: .default)
        timer.fire()
 */
        // 暂停定时刷新的任务，手动更新
        /*
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { (ktimer) in
            
            let hour = self.getHour()
            if(hour != "00" && hour != "12") {
                
                self.freeV2ThisHourSynced = false
                menuController.logger.write("未到更新freev2配置信息的时间，hour: " + hour + ", return")
                return
            }
            
            if(self.freeV2ThisHourSynced){
                
                menuController.logger.write("已经更新freev2配置信息，return")
                return
            }
            
            menuController.logger.write("开始更新freev2配置信息")
            self.freeV2ThisHourSynced = menuController.getFreeV2()
        }
 */
 
    }
    
    private var freeV2ThisHourSynced: Bool = false;
    func getHour() -> String {
        
        let now = Date()
        let dformatter = DateFormatter()
        dformatter.dateFormat = "HH"
        return dformatter.string(from: now)
    }

    func checkDefault() {
        if UserDefaults.get(forKey: .v2rayCoreVersion) == nil {
            UserDefaults.set(forKey: .v2rayCoreVersion, value: V2rayCore.version)
        }
        if UserDefaults.get(forKey: .autoCheckVersion) == nil {
            UserDefaults.setBool(forKey: .autoCheckVersion, value: true)
        }
        if UserDefaults.get(forKey: .autoUpdateServers) == nil {
            UserDefaults.setBool(forKey: .autoUpdateServers, value: true)
        }
        if UserDefaults.get(forKey: .autoSelectFastestServer) == nil {
            UserDefaults.setBool(forKey: .autoSelectFastestServer, value: false)
        }
        if UserDefaults.get(forKey: .autoLaunch) == nil {
            SMLoginItemSetEnabled(launcherAppIdentifier as CFString, true)
            UserDefaults.setBool(forKey: .autoLaunch, value: true)
        }
        if UserDefaults.get(forKey: .runMode) == nil {
            UserDefaults.set(forKey: .runMode, value: RunMode.pac.rawValue)
        }
        if UserDefaults.get(forKey: .gfwPacFileContent) == nil {
            let gfwlist = try? String(contentsOfFile: GFWListFilePath, encoding: String.Encoding.utf8)
            UserDefaults.set(forKey: .gfwPacFileContent, value: gfwlist ?? "")
        }
        if V2rayServer.count() == 0 {
            // add default
            V2rayServer.add(remark: "default", json: "", isValid: false)
        }
    }

    @objc func handleAppleEvent(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let appleEventDescription = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
            return
        }

        guard let appleEventURLString = appleEventDescription.stringValue else {
            return
        }

        _ = URL(string: appleEventURLString)
        // todo
    }

    @objc func onWakeNote(note: NSNotification) {
        print("onWakeNote")
        // reconnect
        if UserDefaults.getBool(forKey: .v2rayTurnOn) {
            V2rayLaunch.Stop()
            V2rayLaunch.Start()
        }
        // check v2ray core
//        V2rayCore().check()
        // auto check updates
        if UserDefaults.getBool(forKey: .autoCheckVersion) {
            // check version
            V2rayUpdater.checkForUpdatesInBackground()
        }
        // auto update subscribe servers
        if UserDefaults.getBool(forKey: .autoUpdateServers) {
            V2raySubSync().sync()
        }
        // ping
        PingSpeed().pingAll()
    }

    @objc func onSleepNote(note: NSNotification) {
        print("onSleepNote")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // unregister All shortcut
        MASShortcutMonitor.shared().unregisterAllShortcuts()
        // Insert code here to tear down your application
        V2rayLaunch.Stop()
        // restore system proxy
        V2rayLaunch.setSystemProxy(mode: .restore)
    }
}
