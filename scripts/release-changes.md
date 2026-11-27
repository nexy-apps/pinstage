## この版の変更（0.2.0）

<!-- 出すたびに、この版の変更に書き直す（make publish が、リリースの説明の先頭と、アプリの中の更新の画面に入れる） -->

- **グループが、メンバーのいるデスクトップについていくようにしました**：グループのウインドウを Mission Control などで別のデスクトップへ移すと、グループも移した先のウインドウバーに並びます。メンバーが分かれたときは、いちばん多くいるデスクトップに出し、グループの行に「1/2」のような印を付けます。印か右クリックの「別のデスクトップのメンバーを外す」で、別のデスクトップのメンバーをグループから外せます
- **ウインドウが 1 つ以下になったグループは、解消するようにしました**：グループからウインドウを外して 1 つ以下になると、確かめてからグループを解消します（ウインドウは閉じません）。「次回からこの確認を出さない」を選んでも、設定の「一般」→「グループを解消する前に確かめる」で戻せます
- **ウインドウスイッチャーから、ドラッグでステージ・グループへ入れられるようにしました**：スイッチャーの下の帯に「ステージ」とグループが出ます。いまのデスクトップのウインドウをドラッグして「ステージ」に落とすとステージに並べ、グループに落とすとそのグループに足します。スペースで選んだウインドウをつかむと、まとめて運べます。スイッチャーの中をマウスで押したあとは、⌥ を離しても閉じません（↩・esc・クリックで閉じます）
- **ウインドウバーの幅を変える縁で、ポインタの形が変わるようにしました**：これまでは、ほかのアプリが前面のときにポインタの形が変わりませんでした

**English:** Groups now follow the desktop where their windows are (with a "1/2" badge and a menu to remove members on other desktops when they are split). A group is dissolved, after confirmation, when it drops to one window or fewer. In the window switcher, you can drag windows onto the stage or onto a group at the bottom. The pointer now changes to a resize cursor on the window bar's resize edge.
