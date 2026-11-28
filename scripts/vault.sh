#!/bin/bash
# 金庫（配る版用の証明書と、更新ファイルの署名の鍵が入った、鍵付きのキーチェーン）を開けて、コマンドを流し、必ず閉める
# （make dist・make publish が呼ぶ）。決まりは、共通のノート「Pinシリーズの決まり」の 4 の節の「金庫の使い方」。
#
# 使い方: vault.sh <コマンド…>
#
# - パスワードは、その場でターミナルで聞く（security unlock-keychain に -p を付けない。付けると、動いている間は
#   ほかのプログラムから見え、ターミナルの履歴にも残るため）
# - 開けている間だけ、金庫を検索リスト（Mac が証明書や鍵を探す箱の一覧）に入れる。Xcode は署名の前に、
#   Sparkle の道具は鍵を探すときに、検索リストの箱しか見ないため。ふだんは入れない（閉まっている金庫を
#   ほかのプログラムが探すと、パスワードの画面が出るため）
# - コマンドが失敗しても、control + C で止めても、金庫を閉めて検索リストを元に戻す
# - パスワードを打てるターミナルから流したときだけ開ける。AI の作業環境のように、ターミナルのないところ
#   （標準入力が端末でないとき）からは開けない（AI は金庫に触れない決まり）
#
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-signing-cert.sh と同じ理由）。
set -euo pipefail

VAULT="$HOME/Library/Keychains/nexy-release.keychain-db"

if [ "$#" -eq 0 ]; then
  echo "使い方: vault.sh <コマンド…>" >&2
  exit 1
fi
if [ ! -t 0 ]; then
  echo "ターミナルのないところ（AI の作業環境など）からは、金庫を開けません。作者の Mac のターミナルで流してください。" >&2
  exit 1
fi
if [ ! -f "${VAULT}" ]; then
  echo "金庫（${VAULT}）がありません。" >&2
  echo "作者なら、控え（.p12 と更新の鍵）から作り直してください（共通のノート「Pinシリーズの決まり」の 4 の節）。" >&2
  exit 1
fi

# いまの検索リスト（終わったら、これに戻す）
ORIG_LIST=()
while IFS= read -r line; do
  ORIG_LIST+=("$(echo "${line}" | sed -E 's/^ *"(.*)"$/\1/')")
done < <(security list-keychains -d user)

cleanup() {
  security list-keychains -d user -s "${ORIG_LIST[@]}" 2>/dev/null || true
  security lock-keychain "${VAULT}" 2>/dev/null || true
  echo "金庫を閉めました。"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

echo "金庫を開けます。金庫のパスワードを入れてください（打っても画面には出ません）。"
security unlock-keychain "${VAULT}"
# 開けてから検索リストに入れる（閉まったまま入れると、その間にほかのプログラムが探して、画面が出ることがあるため）
security list-keychains -d user -s "${ORIG_LIST[@]}" "${VAULT}"

"$@"
