# Sparkle導入による配布・更新方針（GitHub Releases前提）

## 0. 結論
- 専用のファイルサーバーは必須ではない。
- `GitHub Releases` と `GitHub Pages`（またはRaw配信）だけで運用可能。
- Sparkleは `GitHub Release API` を直接たたくのではなく、**`appcast.xml`** を取得して更新先を判断する。
- 更新時はSparkleがアプリ差し替えを実行するため、ユーザーに「古い.appを手動削除させる」運用は不要。

## 1. 配信経路（マッピング）の考え方

### 1.1 Sparkleが参照する情報
アプリ本体に次を埋め込む。
- `SUFeedURL`: appcastの固定URL（毎回同じURL）
- `SUPublicEDKey`: 署名検証用の公開鍵

Sparkleは `SUFeedURL` のXMLを読み、`<enclosure url="...">` で指定されたアーカイブをダウンロードする。

### 1.2 推奨アーキテクチャ（サーバーなし）
- appcast: GitHub Pages上に配置（固定URL）
  - 例: `https://ymuichiro.github.io/koto-type/appcast.xml`
- 配布アーカイブ: GitHub Releasesのasset
  - 例: `https://github.com/ymuichiro/koto-type/releases/download/v1.2.3/KotoType-1.2.3.zip`

この構成なら「URL固定のappcast」と「バージョンごとの実体ファイル」を自然に分離できる。

### 1.3 GitHub Release APIは使うべきか
- Sparkle標準では不要。
- API直接利用は独自実装になり、レート制限・互換性・保守コストが増える。
- 標準の `appcast.xml` 運用が最小リスク。

## 2. インストール/更新の実動作

### 2.1 初回インストール
- 従来通りDMGを配布し、`/Applications` へコピーしてもらう。
- Sparkle更新は書き込み可能な場所にある `.app` が前提。

### 2.2 更新時
1. アプリ起動中にSparkleがappcastを確認
2. 新版があればZIPをダウンロード
3. ダウンロード物の署名を公開鍵で検証
4. 検証成功時のみ、既存アプリを新アプリへ置換
5. 必要なら再起動

補足:
- これは「アンインストーラー」ではなく、**アプリバンドルの更新置換**。
- `~/Library` 配下の設定や履歴は通常維持される。

## 3. 秘密鍵の取り扱い（なぜ安全か）

### 3.1 秘密鍵とは何か
- Apple Developer IDとは別物。
- Sparkle更新署名用のEdDSA秘密鍵。
- この鍵で署名した更新のみを、アプリ内公開鍵で正当と判断できる。

### 3.2 なぜ安全か
- 攻撃者がGitHub Release assetを差し替えても、秘密鍵なしでは正しい署名を作れない。
- アプリは署名検証に失敗した更新を拒否する。
- つまり「配布経路の改ざん」と「なりすまし更新」を防げる。

### 3.3 誰が管理するか（Developer IDなし前提）
- 管理主体: リリース担当者（あなた）
- 原則:
  - 秘密鍵をGitにコミットしない
  - 署名はローカルKeychainまたはCI Secret経由で実行
  - 鍵の暗号化バックアップを複数保持
  - 漏えい時の失効/再配布手順をRunbook化

### 3.4 重要リスク
- 秘密鍵漏えい: 悪意ある更新に署名できてしまう
- 秘密鍵紛失: 既存インストールへの継続配信が困難になる
- したがって、鍵管理は「コード本体」と同等かそれ以上に重要

## 4. このPRで完全対応する場合の方針

### 4.1 変更対象ファイル（想定）
- `KotoType/Package.swift`
- `KotoType/Sources/KotoType/App/AppDelegate.swift`
- `KotoType/Sources/KotoType/UI/MenuBarController.swift`
- `KotoType/scripts/create_app.sh`
- `.github/workflows/release.yml`
- `README.md`
- `docs/operations/`（運用Runbook）

### 4.2 対応事項（実装）
1. Sparkle依存追加とUpdater初期化
2. メニューに「Check for Updates...」追加
3. `Info.plist` に `SUFeedURL` / `SUPublicEDKey` / 更新設定キー追加
4. リリース成果物に `DMG` に加えて `ZIP` を追加
5. `generate_appcast` を使った `appcast.xml` 生成ステップ追加
6. 生成した `appcast.xml` を固定URLへ公開（GitHub Pages）
7. GitHub Actionsで「ビルド→署名→appcast生成→Release添付→appcast公開」を自動化
8. 鍵管理ルール（作成・バックアップ・ローテーション・事故対応）を文書化

### 4.3 対応事項（テスト/検証）
1. 新版検知（appcast読込）
2. 署名正常時の更新成功
3. 署名不正時の更新拒否
4. `/Applications` 配置時の更新成功
5. 読み取り専用配置時に適切に失敗すること

### 4.4 完了条件（Definition of Done）
- タグ作成でReleaseに `DMG` と `ZIP` が添付される
- `appcast.xml` が固定URLで配信される
- 旧版から最新版へアプリ内更新が成功する
- 鍵管理手順がドキュメント化され、運用者が実行可能

## 5. 非機能上の注意（本PR範囲外になり得るもの）
- Developer ID署名/Notarization未導入の場合、初回インストール時のGatekeeper体験は残る。
- ただし、一度インストールされた利用者に対する更新体験はSparkle導入で大幅に改善可能。
