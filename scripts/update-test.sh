#!/bin/bash
# 更新を、手元で通しで試す準備をする（make update-test。手順は docs/TESTING.md の「更新を通しで試す」。Pinshelf と同じ作り）。
#
# ふだんの Pinstage とは別の ID（app.nexy.Pinstage.updatetest）・別の名前（Pinstage UpdateTest）の試験用アプリを、古い版と新しい版の 2 つ作り、
# 新しい版を手元のサーバー（http://localhost:8767）から配る。古い版を開くと、Sparkle が新しい版を見つけて入れ替える。
# いちばん確かめたいのは、入れ替えたあとも、アクセシビリティ（と画面収録）の許可が外れないこと。
# URL スキームも、配る版・開発のビルドとぶつからないよう pinstage-updatetest:// にする。
#
# 古い版の開き方は 2 通り:
# - 手早く: 手元でビルドしたもの（build/update-test/old）を、そのまま開く
# - 配る形に近づけて: サーバーからブラウザでダウンロードし、アプリケーションフォルダに入れて、macOS の確認を通してから開く
#   （ダウンロードの印（quarantine）が付いたままの版から、更新できるかを確かめる）
#
# - 別の ID なので、ふだんの Pinstage の設定と許可には触れず、アプリケーションフォルダにも並べて置ける。
#   ただし、グループと型（Application Support/Pinstage/library.json）は、ふだんの Pinstage と同じファイルを読み書きする
# - 更新ファイルの署名の鍵は、その場で作る試験用のもの（キーチェーンは使わない。リリース用の鍵がなくても試せる）
# - 試験用アプリだけ、手元のサーバー（暗号化なし）から読めるように、通信の例外を足す（配る版には入れない）
#
# 使い方: update-test.sh [xcodebuild に足す引数…]
#   環境変数 SIGN_IDENTITY: アプリの署名に使う証明書（make update-test が、開発用の証明書 nexy Dev Signing を渡す。
#     make update-test ADHOC=1 のときは "-" でアドホック署名。このときは、入れ替えると許可が外れるのが正しい動き）
#   環境変数 UPDATE_TEST_PORT: 手元のサーバーのポート（make update-test が渡す。既定は 8767。Pin シリーズの試験どうしでぶつからないよう、
#     アプリごとに分けている: Pinshelf 8765・Pinshot 8766・Pinstage 8767）
#   環境変数 NO_SERVER=1: アプリと版の一覧を作るだけで、サーバーは動かさない
#
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-signing-cert.sh と同じ理由）。
set -euo pipefail

PORT="${UPDATE_TEST_PORT:?make update-test から流してください（UPDATE_TEST_PORT がありません）}"
SIGN_IDENTITY="${SIGN_IDENTITY:?make update-test から流してください（SIGN_IDENTITY がありません）}"
if [ "${SIGN_IDENTITY}" = "-" ]; then
  SIGN_LABEL="アドホック署名"
  PERMISSION_NOTE="アドホック署名なので、入れ替えると許可が外れるのが正しい動き（証明書で署名したときとの比べ用）"
else
  SIGN_LABEL="証明書「${SIGN_IDENTITY}」で署名"
  PERMISSION_NOTE="古い版と新しい版を同じ証明書で署名しているので、許可が外れないのが正しい動き"
fi
# 試験用アプリの ID・アプリのファイル名・画面に出る名前・URL スキーム（決まりは、共通のノート「Pinシリーズの決まり」の 3 の節）
TEST_ID="app.nexy.Pinstage.updatetest"
TEST_NAME="PinstageUpdateTest"
TEST_DISPLAY_NAME="Pinstage UpdateTest"
TEST_URL_SCHEME="pinstage-updatetest"
ROOT="$(pwd)"
WORK="${ROOT}/build/update-test"
SITE="${WORK}/site"
OLD_APP="${WORK}/old/${TEST_NAME}.app"
NEW_APP="${WORK}/new/${TEST_NAME}.app"
PRODUCT="${WORK}/DerivedData/Build/Products/Release/Pinstage.app"
PLIST_BUDDY=/usr/libexec/PlistBuddy

# 試験用アプリが動いたままだと、作り直した古い版を開いても、動いているほうが前に出るだけになる
if lsappinfo find bundleid="${TEST_ID}" 2>/dev/null | grep -q .; then
  echo "試験用の Pinstage（${TEST_DISPLAY_NAME}）が動いています。終了してから、もう一度流してください。" >&2
  exit 1
fi

# サーバーを動かせるか（ポートが空いているか）を、ビルドの前に確かめる（ビルドには数分かかるので、作り終えてから止まらないように。Pinshot と同じ）。
# サーバーと同じく 127.0.0.1 のそのポートで受け口を開いてみて、開けなければ止める
check_port() {
  python3 - "$1" <<'PY'
import socket, sys
sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError as error:
    sys.exit(error.strerror)
PY
}
if [ "${NO_SERVER:-}" != "1" ] && ! PORT_ERROR="$(check_port "${PORT}" 2>&1)"; then
  echo "手元のサーバーを、ポート ${PORT} で動かせません（${PORT_ERROR}）。" >&2
  echo "Address already in use なら、ほかのものがそのポートを使っています（前に流した試験のサーバーが、別のターミナルで動いたままのことが多い）。" >&2
  echo "何が使っているかは、別のターミナルで  lsof -nP -iTCP:${PORT} -sTCP:LISTEN  を流すと分かります。" >&2
  echo "それを止めてから流し直すか、make update-test UPDATE_TEST_PORT=8800 のように、空いているポートを渡してください。" >&2
  exit 1
fi

# プロジェクトが「書類」などの中にあると、手元でビルドした古い版を入れ替えるときに、macOS がそのフォルダへのアクセスを確かめる
# （入れ替えの部品が、そのフォルダの中のアプリを書き換えるため。配る版はアプリケーションフォルダに置くので、出ない）
FOLDER_NOTE=""
for folder in Documents Desktop Downloads; do
  case "${WORK}/" in
    "${HOME}/${folder}/"*)
      FOLDER_NOTE="     （入れ替えのときに「フォルダ内のファイルにアクセス」と聞かれたら、許可する。このプロジェクトが ~/${folder} の中にあるためで、
      配る版はアプリケーションフォルダに置くので出ない）
"
      ;;
  esac
done

# いまの版（project.yml）を古い版にし、ビルド番号を 1 つ上げたものを新しい版にする
VERSION="$(sed -n 's/.*CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)"
BUILD="$(sed -n 's/.*CFBundleVersion: *"\(.*\)"/\1/p' project.yml)"
NEW_VERSION="${VERSION}.1"
NEW_BUILD="$((BUILD + 1))"

rm -rf "${WORK}/old" "${WORK}/new" "${SITE}" "${WORK}/plists"
mkdir -p "${WORK}/old" "${WORK}/new" "${SITE}/download" "${WORK}/plists"

# 試験用の鍵を作る（1 行目が秘密鍵、2 行目が公開鍵）
echo "試験用の鍵を作っています…"
xcrun swiftc -O -module-cache-path "${WORK}/module-cache" scripts/update-test-key.swift -o "${WORK}/make-key"
# 補助の道具も、アプリと同じ証明書で署名する（アドホック署名にするのは ADHOC=1 のときだけ。決まりの 5 の節）
codesign -f -s "${SIGN_IDENTITY}" "${WORK}/make-key" 2>/dev/null
KEYS="$("${WORK}/make-key")"
KEY_FILE="${WORK}/test-private-key.txt"
echo "${KEYS}" | sed -n 1p > "${KEY_FILE}"
PUBLIC_KEY="$(echo "${KEYS}" | sed -n 2p)"

# 試験用の Info.plist を作る（版・配信元を差し替え、手元のサーバーから読めるようにする。ID・画面の名前・URL スキーム・公開鍵は、
# 開発のビルドと同じく、ビルドの設定（project.yml の PINSTAGE_*）で渡す: build_app）。
# 自動で確かめる間隔は、配る版と同じ 1 時間（Info.plist のまま。Sparkle が受け付けるいちばん短い間隔）
make_plist() {
  local output="$1" build="$2" version="$3"
  cp Pinstage/Info.plist "${output}"
  "${PLIST_BUDDY}" \
    -c "Set :CFBundleVersion ${build}" \
    -c "Set :CFBundleShortVersionString ${version}" \
    -c "Set :SUFeedURL http://localhost:${PORT}/appcast.xml" \
    -c "Add :NSAppTransportSecurity dict" \
    -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" \
    -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" \
    -c "Add :NSAppTransportSecurity:NSExceptionDomains:localhost dict" \
    -c "Add :NSAppTransportSecurity:NSExceptionDomains:localhost:NSExceptionAllowsInsecureHTTPLoads bool true" \
    "${output}" >/dev/null
}

# 配る版と同じ設定（Release）で、試験用の ID のアプリをビルドする（速くするため、この Mac の CPU 向けだけ）
build_app() {
  local plist="$1"
  shift
  if ! xcodebuild -project Pinstage.xcodeproj -scheme Pinstage -sdk macosx -configuration Release \
    -derivedDataPath "${WORK}/DerivedData" CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" ARCHS="$(uname -m)" \
    PRODUCT_BUNDLE_IDENTIFIER="${TEST_ID}" PINSTAGE_DISPLAY_NAME="${TEST_DISPLAY_NAME}" PINSTAGE_URL_SCHEME="${TEST_URL_SCHEME}" \
    PINSTAGE_UPDATE_PUBLIC_KEY="${PUBLIC_KEY}" INFOPLIST_FILE="${plist}" "$@" build >"${WORK}/build.log" 2>&1; then
    tail -30 "${WORK}/build.log"
    echo "ビルドできませんでした（記録: ${WORK}/build.log）" >&2
    exit 1
  fi
}

# アプリを zip にする（配る zip と同じ作り方）
zip_app() {
  ditto -c -k --sequesterRsrc --keepParent "$1" "$2"
}

echo "古い版（${VERSION}・ビルド ${BUILD}・${SIGN_LABEL}）を作っています…"
make_plist "${WORK}/plists/old.plist" "${BUILD}" "${VERSION}"
build_app "${WORK}/plists/old.plist" "$@"
ditto "${PRODUCT}" "${OLD_APP}"
# 配る形に近づけて試すときに、ブラウザでダウンロードする古い版
OLD_ZIP_NAME="${TEST_NAME}-${VERSION}.zip"
zip_app "${OLD_APP}" "${SITE}/download/${OLD_ZIP_NAME}"

echo "新しい版（${NEW_VERSION}・ビルド ${NEW_BUILD}・${SIGN_LABEL}）を作っています…"
make_plist "${WORK}/plists/new.plist" "${NEW_BUILD}" "${NEW_VERSION}"
build_app "${WORK}/plists/new.plist" "$@"
ditto "${PRODUCT}" "${NEW_APP}"
NEW_ZIP="${SITE}/${TEST_NAME}-${NEW_VERSION}.zip"
zip_app "${NEW_APP}" "${NEW_ZIP}"

# 2 つの版の「同じアプリ」の条件（macOS が許可などを覚えるときの目印）。証明書で署名していれば、2 つとも同じになる
OLD_REQUIREMENT="$(codesign -d -r- "${OLD_APP}" 2>&1 | sed -n 's/^designated => //p')"
NEW_REQUIREMENT="$(codesign -d -r- "${NEW_APP}" 2>&1 | sed -n 's/^designated => //p')"

# 版の一覧を作る（試験用の鍵で署名する）
cat > "${WORK}/notes.md" <<EOF
## 更新の試験

- これは、更新を手元で試すための版です（${VERSION} → ${NEW_VERSION}）
- 入れ替わったあと、アクセシビリティの許可が外れていないか、「ログイン時に起動」が入ったままかを確かめます
EOF
SPARKLE_KEY_FILE="${KEY_FILE}" ./scripts/make-appcast.sh "${NEW_ZIP}" "${WORK}/notes.md" "http://localhost:${PORT}/" "${SITE}/appcast.xml"

cat <<EOF

準備ができました（${SIGN_LABEL}）。

  古い版（${VERSION}）: ${OLD_APP}
  新しい版（${NEW_VERSION}）: 手元のサーバーから配ります

  macOS が「同じアプリ」と見なす条件（許可などはこれにひも付く）:
    古い版: ${OLD_REQUIREMENT}
    新しい版: ${NEW_REQUIREMENT}
  （${PERMISSION_NOTE}）

どちらの試し方でも、先に、ふだんの Pinstage と Pinstage Dev を終了しておきます（Pinstage Dev は make stop で止まる。配る版の Pinstage は止まらない）。
試験用アプリの名前は ${TEST_DISPLAY_NAME} です（アプリのファイルは ${TEST_NAME}.app。メニューバーのアイコンとウインドウバーは、ふだんの Pinstage と同じ）。
グループと型は、ふだんの Pinstage と同じファイルを使うので、試験のあいだは書き換えないでおきます（設定と許可は別）。

■ 手早く試す（手元でビルドした古い版から更新する）
  1. 別のターミナルで、古い版を開く:  open "${OLD_APP}"
  2. アクセシビリティの許可を求められたら、システム設定で ${TEST_DISPLAY_NAME} をオンにする。
     設定の「一般」→「macOS の設定」で、アクセシビリティが「許可しています」になったのを確かめ、
     「起動」の「ログイン時に起動」をオンにする
  3. メニューバーのアイコンの右下に下向きの矢印の印が付き、メニューのいちばん上に「新しいバージョン ${NEW_VERSION} があります…」と出る。
     （印は、前に確かめてから 1 時間たっていないと付かない。そのときは、メニューの「アップデートを確認…」で進める）
     印が消えないことを確かめる: それを選び、更新の画面を「あとで通知」で閉じても、印が残るか。
     メニューの「Pinstage を終了」で終了して、もう一度開いても、印が残るか
  4. もう一度「新しいバージョン ${NEW_VERSION} があります…」を選ぶ →「アップデートをインストール」→ ダウンロードのあと「インストールして再起動」
${FOLDER_NOTE}  5. 入れ替わって開き直したら、次を確かめる:
     - アイコンの矢印の印が消え、ふだんのアイコンに戻っているか
     - アクセシビリティの許可を、もう一度求められないか（${PERMISSION_NOTE}）
     - 設定の「一般」→「macOS の設定」のアクセシビリティが「許可しています」のままか。
       ウインドウバーでほかのアプリのウインドウを押すと、前に出て並ぶか
     - 開き直すときに、macOS の確認の画面が出ないか（出たら、押す前にスクリーンショットを撮っておく）
     - 設定の「一般」のバージョンが ${NEW_VERSION} になっているか
     - 「ログイン時に起動」がオンのままか

■ 配る形に近づけて試す（ダウンロードして、macOS の確認を通した古い版から更新する）
  1. ブラウザ（Safari など）で次を開いて、古い版をダウンロードする:
       http://localhost:${PORT}/download/${OLD_ZIP_NAME}
  2. 「ダウンロード」フォルダにできた ${TEST_NAME}.app を、Finder で「アプリケーション」フォルダへ移す
     （zip のままのときは、ダブルクリックで展開してから）
  3. 移した ${TEST_NAME} を開く。「"${TEST_NAME}.app"は開いていません」と止められるので、「完了」を押し（「ゴミ箱に入れる」は押さない）、
     システム設定 →「プライバシーとセキュリティ」の下の方の「このまま開く」を押してから、もう一度開く
     （ここでは、ターミナルの xattr -d では開かない。ダウンロードの印を付けたまま試すため）
     止められずにそのまま開いたときは、そのまま進めてよい（この Mac で一度開いたことのある版は、止められないことがある。
     あとから xattr で印を付けると、別の場所に写して動かす扱い（App Translocation）になり、更新できなくなるので、付けない）
  4. あとは「手早く試す」の 2〜5 と同じ（手早く試したあとなら、許可はもう入っている）

終わったら:
  - 設定の「一般」で「ログイン時に起動」をオフに戻してから、試験用の Pinstage を終了する
    （戻し忘れたときは、システム設定 →「一般」→「ログイン項目」で外す）
  - 試験用アプリの許可と設定を消す（ふだんの Pinstage の許可には触れない）:
       tccutil reset Accessibility ${TEST_ID}
       tccutil reset ScreenCapture ${TEST_ID}
       defaults delete ${TEST_ID}
  - アプリケーションフォルダに入れた ${TEST_NAME}.app は、ゴミ箱に入れる
  - このサーバーを control + C で止める
  - 別のターミナルで make update-test-log を流すと、試験のあいだの macOS の記録が
    ${WORK}/system.log に書き出される（許可が引き継がれたか・確認の画面が出たかの裏取りと、うまくいかないときの手がかり）
EOF

if [ "${NO_SERVER:-}" = "1" ]; then
  exit 0
fi

echo
echo "サーバーを動かしています（http://localhost:${PORT}）…"
exec python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${SITE}"
