import Foundation
import os
import PinstageCore

extension Logger {
    /// Pinstage の記録（Console や make update-test-log では、subsystem「app.nexy.Pinstage」で探す）
    ///
    /// subsystem は、試験用アプリ（ID が違う）でも同じにしておく（記録を同じ条件で探せるように）。
    init(pinstage category: String) {
        self.init(subsystem: "app.nexy.Pinstage", category: category)
    }
}

extension Bundle {
    /// 版（CFBundleShortVersionString。例: 0.3.0）
    var shortVersion: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// ビルド番号（CFBundleVersion。Sparkle は、これで新旧を比べる）
    var buildNumber: String? {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// このアプリの URL スキーム（Info.plist の CFBundleURLTypes。配る版は pinstage、開発のビルドは pinstage-dev。
    /// 設定の「自動化」に出す URL は、動いているアプリのものにする）
    var urlScheme: String {
        let types = object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.first?["CFBundleURLSchemes"] as? [String]
        return schemes?.first ?? PinstageURL.scheme
    }
}
