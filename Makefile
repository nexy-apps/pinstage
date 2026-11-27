DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/Pinstage.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Pinstage.app
INSTALL_BUILT_APP := $(DERIVED_DATA)/Build/Products/Install/Pinstage.app
# 開発のビルド（make build・run・install）の ID。make stop が、配る版を止めないよう、この ID のアプリだけを終了する。
# ID と画面の名前は project.yml の Debug・Install で決めている（変えるときは、ここも合わせる。決まりは共通のノート「Pinシリーズの決まり」の 3 の節）
DEV_BUNDLE_ID := app.nexy.Pinstage.dev
# make install で入れる場所（開発のビルドなので、配る版の Pinstage.app とぶつからないよう「Pinstage Dev.app」の名前で入れる）
INSTALL_DIR ?= /Applications
INSTALL_APP := $(INSTALL_DIR)/Pinstage Dev.app
# アプリの版（project.yml の CFBundleShortVersionString）。1.0.0 より前は β 版
VERSION := $(shell sed -n 's/.*CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)
# β 版として出すときは BETA=1 のように番号を渡す（タグは v0.1.0-beta.1、GitHub ではプレリリースにする）
BETA ?=
RELEASE_NAME := $(VERSION)$(if $(BETA),-beta.$(BETA))
DIST_BASE := dist/Pinstage-$(RELEASE_NAME)
DIST_ZIP := $(DIST_BASE).zip
DIST_DMG := $(DIST_BASE).dmg

# 署名（決まりは、共通のノート「Pinシリーズの決まり」の 4・5 の節と docs/ARCHITECTURE.md の「署名と更新」。Pinshelf と同じ作り）。
# 開発のビルド・更新の試験・補助の道具は、開発用の証明書で署名する（make cert で一度だけ作る）。
# 証明書がなければ止めて案内を出す（黙ってアドホック署名にしない）。ADHOC=1 を付けたときだけ、注意を出してアドホック署名にする。
# 作者以外がソースからビルドするときは、DEV_CERT="〇〇 Dev Signing" のように自分の証明書の名前を渡せる
DEV_CERT ?= nexy Dev Signing
ADHOC ?=
# BETA=1 とそろえて、1 だけを受け付ける（true・yes などは、気づかずに証明書のビルドになるので止める）
ifneq ($(filter-out 1,$(ADHOC)),)
$(error ADHOC には 1 だけを渡せます（いまの値: $(ADHOC)）。アドホック署名にするときは ADHOC=1、しないときは付けない)
endif
DEV_SIGN := $(if $(filter 1,$(ADHOC)),-,$(DEV_CERT))
# ビルドしたアプリが、想定の署名（開発用の証明書。ADHOC=1 のときはアドホック署名）になったかを確かめる。
# 開発用の証明書は人ごとに違い、指紋を決めておけないので、名前で見る（配る版は signing-check.sh で指紋を見る）
DEV_SIGN_WANT := $(if $(filter 1,$(ADHOC)),Signature=adhoc,Authority=$(DEV_CERT))
check_dev_signed = codesign -dvv "$(1)" 2>&1 | grep -qxF "$(DEV_SIGN_WANT)" || { \
	echo "$(1) が、想定の署名（$(DEV_SIGN_WANT)）になっていません。いまの署名:" >&2; \
	codesign -dvv "$(1)" 2>&1 | grep -E '^(Authority|Signature)=' >&2; exit 1; }
# 配る版（make dist・make publish）は、作者の金庫の中の「nexy Release Signing」で署名する。証明書は project.yml の
# Release の CODE_SIGN_IDENTITY（SHA-1）で決めていて、ここではビルドの前後の確かめのために読む。ADHOC=1 は効かない。
# 金庫は scripts/vault.sh が開けて、必ず閉める
RELEASE_SIGN_IDENTITY = $(or $(shell sed -n 's/^ *CODE_SIGN_IDENTITY: *\([0-9A-F]\{40\}\) *$$/\1/p' project.yml),\
	$(error project.yml の Release に、CODE_SIGN_IDENTITY（証明書の SHA-1）がありません))
# 金庫の中の、更新ファイルに署名する鍵のアカウント名（Sparkle の道具に渡す）
SPARKLE_ACCOUNT := nexy-release
# Launch Services（アプリの場所とアイコンを覚えている macOS の仕組み）に、アプリを登録し直す道具
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# $(call register_app,アプリの場所): アプリを Launch Services に登録し直す（失敗しても止めない）
register_app = touch "$(1)"; $(LSREGISTER) -f "$(1)" >/dev/null 2>&1 || true
# xcodebuild に足す引数（ふだんは空）
XCODEBUILD_FLAGS ?=

XCODEBUILD := xcodebuild -project Pinstage.xcodeproj -scheme Pinstage -sdk macosx \
	-derivedDataPath $(DERIVED_DATA) $(XCODEBUILD_FLAGS)

# 更新の仕組み（Sparkle）。公式の配布物を取り寄せて Vendor/Sparkle に置く（リポジトリには入れない。Pinshelf と同じ版）。
# 版を上げるときは、SPARKLE_VERSION と SPARKLE_SHA256（配布物 Sparkle-版.tar.xz の SHA-256）を一緒に変える
SPARKLE_VERSION := 2.10.1
SPARKLE_SHA256 := 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_DIR := Vendor/Sparkle
# 取り寄せた版の印（版を上げると名前が変わり、取り寄せ直す）
SPARKLE_STAMP := $(SPARKLE_DIR)/.version-$(SPARKLE_VERSION)
# 更新ファイルの署名を確かめる公開鍵（project.yml の PINSTAGE_UPDATE_PUBLIC_KEY）
# （最初の 1 行だけ読む。Debug・Install の空の値は読まない。make publish でだけ使うので、使うときに読む）
UPDATE_PUBLIC_KEY = $(shell sed -n '/^ *PINSTAGE_UPDATE_PUBLIC_KEY: *"\(.*\)"/{s//\1/p;q;}' project.yml)
# Release を作るリポジトリ（手元には写しの yzanbo などほかの送り先もあるので、gh にはいつもこれを渡す）
GITHUB_REPO := nexy-apps/pinstage
# 配る更新ファイル（zip）を置く場所。版の一覧（appcast.xml）の中のダウンロード元になる
RELEASE_DOWNLOAD_URL := https://github.com/$(GITHUB_REPO)/releases/download/v$(RELEASE_NAME)/
# 版の一覧（appcast.xml）を置く場所。組織 nexy-apps の GitHub Pages（https://nexy-apps.github.io/pinstage/appcast.xml）。
# アプリのリポジトリには置かない（make publish が、置き場所のリポジトリに書き込んで送る）
APPCAST_REPO := https://github.com/nexy-apps/nexy-apps.github.io.git
APPCAST_SITE := build/appcast-site
APPCAST_FILE := pinstage/appcast.xml
# 更新の試験で、新しい版を配る手元のサーバーのポート（Pin シリーズの試験どうしでぶつからないよう、Pinshelf は 8765、Pinshot は 8766）。
# ほかで使っているときは make update-test UPDATE_TEST_PORT=8800 のように替える
UPDATE_TEST_PORT ?= 8767

.PHONY: generate build release dist dist-in-vault publish publish-in-vault appcast-site run stop install install-build uninstall \
	test clean cert setup icon preview readme-images sparkle update-test update-test-log dev-signing

# アイコンを描くスクリプトをビルドする場所
ICON_TOOL_DIR := $(DERIVED_DATA)/icon-tool

# project.yml から Pinstage.xcodeproj を作る（ファイルを足したときも、これで入る）
generate: $(SPARKLE_STAMP)
	xcodegen generate

# Sparkle（更新の仕組み）を取り寄せる。ビルドの前に自動で行うので、ふだんは自分で呼ばなくてよい。
# 取り寄せたファイルは、決めてある SHA-256 と合うことを確かめてから使う（合わなければ止まる）
sparkle: $(SPARKLE_STAMP)

$(SPARKLE_STAMP):
	rm -rf "$(SPARKLE_DIR)"
	mkdir -p "$(SPARKLE_DIR)"
	curl -fsSL -o "$(SPARKLE_DIR)/Sparkle.tar.xz" \
		"https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz"
	echo "$(SPARKLE_SHA256)  $(SPARKLE_DIR)/Sparkle.tar.xz" | shasum -a 256 -c -
	@# 使うものだけ取り出す: アプリに入れるフレームワーク・署名と版の一覧の道具・ライセンス
	tar -xJf "$(SPARKLE_DIR)/Sparkle.tar.xz" -C "$(SPARKLE_DIR)" ./Sparkle.framework ./bin ./LICENSE
	rm "$(SPARKLE_DIR)/Sparkle.tar.xz"
	@# Sparkle のライセンスは、配るものに全文を含める決まりなので、アプリに同梱するファイルへ写す（リポジトリに入れる）
	mkdir -p Pinstage/Licenses
	cp "$(SPARKLE_DIR)/LICENSE" Pinstage/Licenses/Sparkle.txt
	touch "$@"

# 開発用の証明書があるかを確かめる（なければ止めて案内を出す）。ADHOC=1 のときは、注意を出してアドホック署名にする
dev-signing:
ifeq ($(ADHOC),1)
	@echo "注意: 証明書なし（アドホック署名）でビルドします。ビルドのたびに、アクセシビリティなどの許可を取り直すことになります。"
else
	@security find-identity -v -p codesigning 2>/dev/null | grep -qF '"$(DEV_CERT)"' || { \
		echo "開発用の証明書「$(DEV_CERT)」が、この Mac にありません。" >&2; \
		echo "最初に 1 回だけ make cert を流してください（証明書なしでビルドするときは ADHOC=1 を付ける）。" >&2; \
		exit 1; }
	@echo "署名: $(DEV_SIGN)"
endif

# 開発用（Debug）にビルドする（ID は app.nexy.Pinstage.dev・画面の名前は Pinstage Dev・開発用の証明書）
build: generate dev-signing
	$(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="$(DEV_SIGN)" build
	@$(call check_dev_signed,$(APP))

# 配る版の設定（Release）でビルドする。Intel と Apple Silicon の両方で動く形にする。
# 配る版用の証明書で署名するので、金庫が開いている必要がある（make dist から使う。ひとりで流すと、署名で止まる）
release: generate
	$(XCODEBUILD) -configuration Release ONLY_ACTIVE_ARCH=NO build

# GitHub の Releases に置く DMG と zip を作る（dist/Pinstage-版.dmg・.zip・.sha256）。
# DMG は、開くと Pinstage.app とアプリケーションフォルダが並び、ドラッグで入れられる形にする。
# 配る版は、作者の金庫の中の「nexy Release Signing」で署名する（どの版も同じ証明書で署名して、更新しても許可が外れないように）。
# 金庫は scripts/vault.sh が開け（パスワードをその場で聞く）、終わったら（失敗しても）必ず閉める。
# ビルドの前に証明書があるかを、ビルドのあとに正しい証明書で署名されたかを確かめる
dist:
	./scripts/vault.sh $(MAKE) dist-in-vault

# 金庫を開けたあとの、make dist の中身（make dist と make publish から使う。ひとりでは流さない）
dist-in-vault:
	./scripts/signing-check.sh keychain "$(RELEASE_SIGN_IDENTITY)"
	$(MAKE) release
	./scripts/signing-check.sh app "$(RELEASE_APP)" "$(RELEASE_SIGN_IDENTITY)"
	mkdir -p dist
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" "$(DIST_ZIP)"
	rm -rf dist/dmg-root
	mkdir -p dist/dmg-root
	ditto "$(RELEASE_APP)" dist/dmg-root/Pinstage.app
	ln -s /Applications dist/dmg-root/Applications
	@# macOS 26 以降は diskutil image で作る（hdiutil create は「使わなくなる」と警告が出るため）。ない版では hdiutil で作る
	rm -f "$(DIST_DMG)"
	if diskutil image create from -h >/dev/null 2>&1; then \
		diskutil image create from --format UDZO --volumeName "Pinstage" dist/dmg-root "$(DIST_DMG)"; \
	else \
		hdiutil create -volname "Pinstage" -srcfolder dist/dmg-root -ov -format UDZO "$(DIST_DMG)"; \
	fi
	rm -rf dist/dmg-root
	cd dist && shasum -a 256 "Pinstage-$(RELEASE_NAME).dmg" "Pinstage-$(RELEASE_NAME).zip" > "Pinstage-$(RELEASE_NAME).sha256"
	@echo ""
	@echo "$(DIST_DMG) と $(DIST_ZIP) を作りました（版: $(RELEASE_NAME)）"

# DMG と zip を作り、GitHub に Release（タグ v版）を作ってアップロードする（GitHub CLI を使う）。
# 説明は「この版の変更」（scripts/release-changes.md。出すたびに書き直す）と「ダウンロードと開き方」をつなげる。
# β 版のときは、説明の先頭に β 版の注意を付け、プレリリースにする。
#
# 入れてもらったアプリに更新を届けるため、zip に金庫の中の鍵で署名して、版の一覧（appcast.xml）を作り、
# 置き場所のリポジトリ（nexy-apps/nexy-apps.github.io）の pinstage/appcast.xml に書き込んで送る（アプリの main には何も送らない）。
# 金庫は最初に 1 回だけ開ける（パスワードを聞く）。先に、main が GitHub と同じか・この版をまだ出していないかを確かめ、
# 版の一覧の置き場所を取ってくる（通信で失敗したときに、金庫を開けてビルドしたあとで止まらないように）
publish: $(SPARKLE_STAMP)
	./scripts/publish-check.sh git "$(RELEASE_NAME)"
	$(MAKE) appcast-site
	./scripts/vault.sh $(MAKE) publish-in-vault

# 版の一覧の置き場所のリポジトリを、手元に取ってくる（前に取ってあれば、GitHub の最新に合わせる。歴史は要らないので最新だけ）
appcast-site:
	if [ -d "$(APPCAST_SITE)/.git" ]; then git -C "$(APPCAST_SITE)" fetch -q --depth 1 origin main && git -C "$(APPCAST_SITE)" reset -q --hard origin/main; \
	else rm -rf "$(APPCAST_SITE)" && git clone -q --depth 1 "$(APPCAST_REPO)" "$(APPCAST_SITE)"; fi

# 金庫を開けたあとの、make publish の中身（make publish から使う。ひとりでは流さない）
publish-in-vault:
	./scripts/publish-check.sh key "$(UPDATE_PUBLIC_KEY)" "$(SPARKLE_ACCOUNT)"
	$(MAKE) dist-in-vault
	( $(if $(BETA),cat scripts/release-notes-beta.md; echo;) cat scripts/release-changes.md; echo; cat scripts/release-notes.md ) > dist/release-notes.md
	mkdir -p "$(dir $(APPCAST_SITE)/$(APPCAST_FILE))"
	SPARKLE_ACCOUNT="$(SPARKLE_ACCOUNT)" ./scripts/make-appcast.sh "$(DIST_ZIP)" scripts/release-changes.md "$(RELEASE_DOWNLOAD_URL)" "$(APPCAST_SITE)/$(APPCAST_FILE)"
	gh release create "v$(RELEASE_NAME)" "$(DIST_DMG)" "$(DIST_ZIP)" "$(DIST_BASE).sha256" --repo "$(GITHUB_REPO)" \
		--target main --title "Pinstage $(RELEASE_NAME)$(if $(BETA), (β 版))" $(if $(BETA),--prerelease) \
		--notes-file dist/release-notes.md
	git -C "$(APPCAST_SITE)" add "$(APPCAST_FILE)"
	git -C "$(APPCAST_SITE)" commit -q -m "chore: Pinstage の版の一覧を $(RELEASE_NAME) にする" -- "$(APPCAST_FILE)"
	git -C "$(APPCAST_SITE)" push -q origin main
	@echo ""
	@echo "$(RELEASE_NAME) を公開しました。版の一覧は数分で https://nexy-apps.github.io/$(APPCAST_FILE) に出て、入れてもらったアプリに新しい版が届きます。"

# 更新を、手元で通しで試す（docs/TESTING.md の「更新を通しで試す」）。
# ふだんの Pinstage とは別の ID の試験用アプリを、開発用の証明書で 2 つの版作り、新しい版を手元のサーバーから配る（止めるときは control + C）
update-test: generate dev-signing
	SIGN_IDENTITY="$(DEV_SIGN)" UPDATE_TEST_PORT="$(UPDATE_TEST_PORT)" ./scripts/update-test.sh $(XCODEBUILD_FLAGS)

# 更新の試験のあいだの macOS の記録を、build/update-test/system.log に書き出す
# （許可が引き継がれたか・確認の画面が出たかの裏取りと、うまくいかないときの手がかりに使う）。
# いつからの記録かは SINCE="2026-11-26 19:50:00" のように渡す（なければ、直近 30 分）
update-test-log:
	./scripts/update-test-log.sh

# 動いている Pinstage Dev を終了してから、ビルドした新しい版を起動する。
# 終了した直後は、Launch Services がまだ「動いている」と思っていて、open が
# 「_LSOpenURLsWithCompletionHandler() failed with error -600」で失敗することがあるので、少し待ってやり直す
run: build stop
	@$(call register_app,$(APP))
	@for i in 1 2 3 4 5; do open "$(APP)" 2>/dev/null && exit 0; sleep 0.5; done; open "$(APP)"

# 動いている開発のビルド（Pinstage Dev）を終了する（配る版の Pinstage は止めない。最大 8 秒待つ）
stop:
	-@for asn in $$(lsappinfo find bundleid=$(DEV_BUNDLE_ID) 2>/dev/null); do \
		pid=$$(lsappinfo info -only pid "$$asn" 2>/dev/null | sed -n 's/.*=//p'); \
		[ -n "$$pid" ] && kill "$$pid" 2>/dev/null; \
	done; \
	for i in $$(seq 1 80); do lsappinfo find bundleid=$(DEV_BUNDLE_ID) 2>/dev/null | grep -q . || break; sleep 0.1; done

# 配る版と同じ作り（project.yml の Install）でビルドし、開発のビルドとして「Pinstage Dev.app」の名前でアプリケーションフォルダに入れる
# （前に入れたものは置き換える。ID は app.nexy.Pinstage.dev・開発用の証明書なので、配る版の Pinstage とは別のアプリとして並ぶ）。
# 動いている Pinstage Dev は、ビルドが終わってから止める
install: install-build stop
	mkdir -p "$(INSTALL_APP)"
	rsync -a --delete "$(INSTALL_BUILT_APP)/" "$(INSTALL_APP)/"
	@$(call register_app,$(INSTALL_APP))
	@echo ""
	@echo "$(INSTALL_APP) に入れました。アプリケーションフォルダから Pinstage Dev を開いてください。"

install-build: generate dev-signing
	$(XCODEBUILD) -configuration Install ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="$(DEV_SIGN)" build
	@$(call check_dev_signed,$(INSTALL_BUILT_APP))

# アプリケーションフォルダから Pinstage Dev を消す（グループと設定は残る）
uninstall: stop
	rm -rf "$(INSTALL_APP)"

# テストを動かす（アプリは起動しない。PinstageCore の swift test で流すので、署名は要らない）。
# AI の作業環境の砂場では、swift test がそのままでは動かないので、いつも砂場の中でも動く形
# （--disable-sandbox・モジュールのキャッシュの場所）で流す（ふつうのターミナルでも結果は変わらない。git hooks から流れるときも同じ）
SWIFT_TEST_FLAGS ?= --disable-sandbox -Xswiftc -disable-sandbox
export CLANG_MODULE_CACHE_PATH ?= $(or $(TMPDIR),/tmp)/clang-module-cache
test:
	cd PinstageCore && swift test $(SWIFT_TEST_FLAGS)

# 最初に 1 回だけ流す: GitHub に送る前（push の前）に自動テストを流す git hooks（.githooks/pre-push）を有効にする
setup:
	git config core.hooksPath .githooks
	@echo "git hooks を有効にしました。git push の前に make test が流れます。"

clean:
	rm -rf $(DERIVED_DATA) PinstageCore/.build build/update-test $(APPCAST_SITE)

# 画面の見た目を、見本のデータで画像に描き出す（アプリを起動せずに見た目を確かめる。build/preview に書き出す）。
# ストリップ（見た目ごと。左に置いたとき・下に置いたとき・アイコンの並びを 1 列まで狭めたとき）と、グループの編集画面・型の編集画面・検索・設定のタブ（一般・ウインドウバー・ウインドウスイッチャー・型・ショートカット・自動化）
PREVIEW_LOOKS := grid gridLarge list listLarge thumbnail thumbnailLarge
PREVIEW_VIEWS := groupEditor layoutEditor search desktopPicker desktopOverview desktopOverviewIcons desktopOverviewThumbnails desktopDisplayGroups layouts general strip switcher shortcuts automation
preview: build
	mkdir -p build/preview
	@for look in $(PREVIEW_LOOKS); do \
		"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-$$look.png" $$look 230 >/dev/null 2>&1; \
		"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-bottom-$$look.png" $$look 1280 normal bottom >/dev/null 2>&1; \
	done
	@for look in grid gridLarge; do \
		"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-$$look-1column.png" $$look 52 >/dev/null 2>&1; \
	done
	@for view in $(PREVIEW_VIEWS); do \
		"$(APP)/Contents/MacOS/Pinstage" --render-view-preview "build/preview/view-$$view.png" $$view >/dev/null 2>&1; \
	done
	@"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-desktopDisplayGroups.png" grid 230 desktopDisplayGroups >/dev/null 2>&1
	@echo "build/preview に書き出しました"

# README の見本の画像を作り直す（見た目を変えたとき。docs/images に書き出す。Pinshelf・Pinshot と同じ考え方）。
# ウインドウバーとウインドウスイッチャーは、make preview と同じく、開発用のビルドで見本のデータを描く（画面には出さない）
readme-images: build
	"$(APP)/Contents/MacOS/Pinstage" --render-readme-images docs/images

# アプリのアイコンを描き直す（scripts/make-app-icon.swift を変えたとき。Pinstage/Assets.xcassets に書き出す）。
# 補助の道具も、開発用の証明書で署名する（アドホック署名にするのは ADHOC=1 のときだけ）
icon: dev-signing
	mkdir -p $(ICON_TOOL_DIR)
	swiftc -O -module-cache-path $(ICON_TOOL_DIR)/cache scripts/make-app-icon.swift -o $(ICON_TOOL_DIR)/make-app-icon
	codesign -f -s "$(DEV_SIGN)" $(ICON_TOOL_DIR)/make-app-icon
	$(ICON_TOOL_DIR)/make-app-icon

# 開発用の証明書（DEV_CERT。作者は「nexy Dev Signing」）を作る（最初に一度だけ。あれば作らず、その SHA-1 を出す。
# 途中で、Mac のログインパスワードを聞かれる）。配る版用の証明書と金庫は別のもので、作者だけが持つ（Pinshelf の scripts/create-nexy-keys.sh で作った）
cert:
	./scripts/create-signing-cert.sh "$(DEV_CERT)"
