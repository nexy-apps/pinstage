#!/bin/bash
# 公開（make publish）の前に確かめる。そろっていなければ、何も作らずに止める。
#
# 使い方:
#   publish-check.sh git <出す版（例: 0.1.0-beta.1）>
#     - main にいて、コミットしていない変更がなく、GitHub の main と同じ
#       （Release のタグは GitHub の main に付くため）
#     - この版（タグ v<版>）を、まだ GitHub に公開していない（版を上げ忘れたまま流すと、DMG と zip を作り、
#       版の一覧を作ったところで、Release を作れずに止まるため）
#   publish-check.sh key <project.yml の公開鍵> <金庫の中の鍵のアカウント名>
#     - 金庫の中の、更新ファイルに署名する鍵が、アプリに入れる公開鍵と合っている
#       （合わない鍵で署名すると、入れてもらったアプリが更新を受け付けなくなる）。金庫を開けたあとに流す
set -euo pipefail

BIN="Vendor/Sparkle/bin"
USAGE="使い方: publish-check.sh git <版> | key <公開鍵> <アカウント名>"

case "${1:-}" in
  git)
    [ "$#" -eq 2 ] || { echo "${USAGE}" >&2; exit 1; }
    RELEASE_NAME="$2"
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
      echo "main ではないブランチにいます。PR をマージしたあと、git checkout main && git pull をしてから、公開してください。" >&2
      exit 1
    fi
    if [ -n "$(git status --porcelain)" ]; then
      echo "コミットしていない変更があります。コミットしてプッシュしてから、公開してください。" >&2
      exit 1
    fi
    git fetch -q origin main
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
      echo "手元の main が、GitHub の main と違います。プッシュ（か pull）してから、公開してください。" >&2
      exit 1
    fi
    if [ -n "$(git ls-remote --tags origin "refs/tags/v${RELEASE_NAME}")" ]; then
      echo "v${RELEASE_NAME} は、もう公開しています。版とビルド番号を上げた変更（PR）を main に入れてから、公開してください。" >&2
      exit 1
    fi
    ;;
  key)
    [ "$#" -eq 3 ] || { echo "${USAGE}" >&2; exit 1; }
    EXPECTED_KEY="$2"
    ACCOUNT="$3"
    if [ -z "${EXPECTED_KEY}" ]; then
      echo "project.yml に、更新ファイルの署名を確かめる公開鍵（PINSTAGE_UPDATE_PUBLIC_KEY）がありません。" >&2
      exit 1
    fi
    VAULT_KEY="$("${BIN}/generate_keys" --account "${ACCOUNT}" -p 2>/dev/null || true)"
    if [ "${VAULT_KEY}" != "${EXPECTED_KEY}" ]; then
      echo "金庫の中の更新ファイルの署名の鍵（アカウント名 ${ACCOUNT}）が、project.yml の公開鍵と合いません。" >&2
      echo "金庫を作り直したときは、控えのファイルを取り込んでください（共通のノート「Pinシリーズの決まり」の 4 の節）。" >&2
      exit 1
    fi
    ;;
  *)
    echo "${USAGE}" >&2
    exit 1
    ;;
esac
