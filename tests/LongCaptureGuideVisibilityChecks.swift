import AppKit
import CoreGraphics
// Integration check: start a public long-capture region in the installed app,
// then run this executable. Reads only LibreShot WindowServer metadata.
// Sharing state proves the AppKit policy; remote-client rendering must also
// be confirmed on the client. It does not assert remote visibility from metadata.
guard let app=NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.allensong.LibreShot" }) else {
    fputs("FAIL: installed LibreShot must be running with a public long-capture region\n", stderr)
    exit(2)
}
let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as! [[String:Any]]
let own=windows.filter { $0[kCGWindowOwnerPID as String] as? Int == Int(app.processIdentifier) && $0[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.screenSaverWindow)) }
let states=own.compactMap { $0[kCGWindowSharingState as String] as? Int }
let result:[String:Any] = ["visibleLongCaptureWindowCount":own.count,"sharingStates":states,"allWindowSharingReadOnly":own.count >= 5 && states.count == own.count && states.allSatisfy{$0==1}]
let data=try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
print(String(data:data,encoding:.utf8)!)
exit(result["allWindowSharingReadOnly"] as! Bool ? 0 : 1)
