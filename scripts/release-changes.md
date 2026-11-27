## この版について（0.1.0）

<!-- 出すたびに、この版の変更に書き直す（make publish が、リリースの説明の先頭と、アプリの中の更新の画面に入れる） -->

アプリの ID と署名を新しくして、0.1.0 から出し直した最初の版です。機能は 0.3.0-beta.1 と同じです（アプリの中からの更新・新しい版の印を含む）。

- アプリの ID を `app.nexy.Pinstage` にしました。前の β 版（ID `app.pinstage.Pinstage`）とは別のアプリとして扱われるので、前の版からは更新されません。前の版を使っていた場合は、ここから入れ直してください（前の版はゴミ箱に入れてかまいません）
- 別のアプリとして扱われるので、アクセシビリティ（と画面収録）の許可は、もう一度取り直します（システム設定の一覧で古い Pinstage を「−」で消してから、新しい Pinstage をオンにします）。グループと登録した型は、そのまま引き継がれます。ショートカットやウインドウバーなどの設定は、初めの状態に戻ります
- 作者の証明書（nexy Release Signing）で署名するようにしました。これから先の版は、どれも同じ証明書で署名するので、更新しても許可はそのまま引き継がれます

**English:** This is the first release after changing the app ID to `app.nexy.Pinstage` and signing it with the author's own certificate (nexy Release Signing). Features are the same as 0.3.0-beta.1. It does not update from earlier betas (different app ID), so please install it fresh and grant Accessibility (and Screen Recording) permission again. Groups and layouts are kept; other settings start from the defaults. Future versions are signed with the same certificate, so permissions will be kept across updates.
