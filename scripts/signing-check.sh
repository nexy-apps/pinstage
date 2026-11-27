#!/bin/bash
# 配る版に署名する証明書を確かめる（make dist が、金庫を開けたあとに呼ぶ）。
#
# 配る版は、作者の「nexy Release Signing」（金庫の中）を、名前ではなく SHA-1 で選んで署名する（project.yml の Release の CODE_SIGN_IDENTITY）。
# 名前は誰でも同じものを作れるので、SHA-1 で選ぶ。作り直した証明書や、同じ名前の別の証明書では、そもそも署名できない。
# ここでは、その証明書が見つからないときに案内を出し、署名のあとに、その証明書で署名されたかを確かめる。
#
# 使い方:
#   signing-check.sh keychain <証明書の SHA-1>        この Mac に、その証明書があるか（ビルドの前）
#   signing-check.sh app <アプリ> <証明書の SHA-1>    ビルドしたアプリが、その証明書で署名されているか（ビルドのあと）
#
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-signing-cert.sh と同じ理由）。
set -euo pipefail

USAGE="使い方: signing-check.sh keychain <証明書の SHA-1> | app <アプリ> <証明書の SHA-1>"

case "${1:-}" in
  keychain)
    [ "$#" -eq 2 ] || { echo "${USAGE}" >&2; exit 1; }
    if ! security find-identity -v -p codesigning | grep -qi "$2"; then
      echo "配る版に署名する証明書（nexy Release Signing・SHA-1: $2）が、開けた金庫の中に見つかりません。" >&2
      echo "金庫を作り直したときは、控え（.p12）を金庫に取り込んでください（共通のノート「Pinシリーズの決まり」の 4 の節）。" >&2
      echo "新しく作った証明書は別物なので、それで配ると、入れてもらったアプリが別のアプリ扱いになります。" >&2
      exit 1
    fi
    ;;
  app)
    [ "$#" -eq 3 ] || { echo "${USAGE}" >&2; exit 1; }
    APP="$2"
    EXPECTED="$(echo "$3" | tr '[:upper:]' '[:lower:]')"
    REQUIREMENT="$(codesign -d -r- "${APP}" 2>&1)"
    if ! echo "${REQUIREMENT}" | grep -qF "certificate leaf = H\"${EXPECTED}\""; then
      echo "${APP} が、配る版の証明書（SHA-1: $3）で署名されていません:" >&2
      echo "${REQUIREMENT}" >&2
      exit 1
    fi
    codesign --verify --deep --strict "${APP}"
    echo "署名を確かめました: ${APP}（証明書の SHA-1: $3）"
    ;;
  *)
    echo "${USAGE}" >&2
    exit 1
    ;;
esac
