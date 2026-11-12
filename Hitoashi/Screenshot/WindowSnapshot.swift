//
//  WindowSnapshot.swift
//  Hitoashi
//
//  Mac 版のウインドウの見た目を、アプリ自身が PNG にして標準出力へ書き出す（DEBUG のビルドだけ）。
//  画面収録の許可が無い環境でも、Mac 版の画面を確かめられるようにするため。
//
//    Hitoashi.app/Contents/MacOS/Hitoashi -screenshot-demo YES -screenshot-scene home -window-snapshot YES > out.txt
//
//  出力の WINDOW-PNG-BEGIN と WINDOW-PNG-END の間が、base64 にした PNG。地図（MapKit）は写らない。
//  Mac では、引数は必ず「-キー 値」の組で渡す。組になっていない引数があると、AppKit がファイルを開く要求として扱い、
//  最初のウインドウが開かない。
//

#if DEBUG && os(macOS)
import AppKit

enum WindowSnapshot {
    static let isRequested = ProcessInfo.processInfo.arguments.contains("-window-snapshot")

    /// 画面が落ち着くのを待ってから、最初のウインドウを PNG にして書き出し、アプリを終える
    static func exportIfRequested() async {
        guard isRequested else {
            return
        }
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: \.isVisible),
              let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSApp.terminate(nil)
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            print("WINDOW-PNG-BEGIN")
            print(data.base64EncodedString())
            print("WINDOW-PNG-END")
            fflush(stdout)
        }
        NSApp.terminate(nil)
    }
}
#endif
