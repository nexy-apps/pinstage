## ダウンロードと開き方

1. 下の `Pinstage-<版>.dmg` をダウンロードして開き、`Pinstage` を `Applications`（アプリケーションフォルダ）へドラッグします（`.zip` は展開して `Pinstage.app` を入れる形です。中身は同じ）
2. 初めて開くと、「"Pinstage.app"は開いていません」（Apple はマルウェアが含まれていないことを検証できませんでした）と止められます（Apple の公証を受けていないため）。次のどちらかで開けます。一度開けば、次からは止められません

   **システム設定から（おすすめ）**
   1. 「完了」を押す（「ゴミ箱に入れる」は押さない）
   2. システム設定 →「プライバシーとセキュリティ」を開き、下のほうへスクロールする
   3. 「"Pinstage.app"は開いていません…」の横の「このまま開く」を押す
   4. パスワードか Touch ID で確かめたら、もう一度 Pinstage を開く

   **ターミナルから**
   1. 「完了」を押す
   2. ターミナルで `xattr -dr com.apple.quarantine /Applications/Pinstage.app` を流す
   3. Pinstage を開く
3. 初めて開くと「アクセシビリティ」の許可を求められます。システム設定で Pinstage をオンにしてください（ほかのアプリのウインドウを動かす・前に出すために使います）
   - ウインドウバーの形式を「サムネイル」にしたときだけ、「画面収録」の許可も求められます（使わなければ不要です）
4. メニューバーに Pinstage のアイコンが出て、画面の左端にウインドウバーが出ます。macOS のステージマネージャはオフにしてください（オンだと、並べたとおりになりません）

入れたあとは、アプリの中から新しい版に更新できます（メニューバーのアイコン →「アップデートを確認…」。自動でも確かめます）。更新のときは、手順 2 も、許可の取り直しも要りません。

本物の Pinstage は、この Releases からだけ配っています。ほかの場所で配られているものは、作者が作ったものではありません。

macOS 26 以降が必要です。Intel と Apple Silicon のどちらの Mac でも動きます。

ソースからビルドする方法は [README](https://github.com/nexy-apps/pinstage#readme) を見てください。

---

**English:** Requires macOS 26 or later. Download the dmg (or zip), drag `Pinstage.app` to Applications, open it once and choose "Done" (not "Move to Trash") on the "“Pinstage.app” Not Opened" dialog, then allow it in System Settings → Privacy & Security ("Open Anyway"), or run `xattr -dr com.apple.quarantine /Applications/Pinstage.app`. Grant Accessibility permission when asked (Screen Recording is only needed for thumbnails). The app is signed with the author's own certificate (not a Developer ID) and is not notarized. Once installed, it updates itself from the menu bar ("アップデートを確認…") and keeps its permissions. Official builds are distributed only from these GitHub Releases. Turn off macOS Stage Manager while using Pinstage.
