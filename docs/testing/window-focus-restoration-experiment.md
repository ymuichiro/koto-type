# Window Focus Restoration Experiment Report

実施日: 2026-07-17

## 目的

文字起こし開始時のアプリ／ウィンドウを保存し、文字起こし完了時に必要な場合だけ保存済みウィンドウをAccessibility APIで前面化できるかを確認した。

仕様は次のとおりとした。

1. 現在のウィンドウが保存済みウィンドウと同じなら何もしない。
2. 異なる場合だけ、保存済みウィンドウを前面化する。
3. ウィンドウの取得・アクティブ化・前面化に失敗した場合は、追加のフォーカス操作をせず、既存の現在フォーカスへの貼り付け処理を続ける。
4. マウスイベントを生成せず、物理的なマウスポインタを移動させない。

## 実験結果

### Accessibility APIのコンパイル

`AppKit` と `ApplicationServices` を使った最小プローブを `swiftc` でコンパイルできた。

```text
xcrun swiftc window_focus_probe.swift -o /tmp/kototype-window-focus-probe
```

結果: 成功。

### システム全体のフォーカス取得

実験プロセスのAccessibility権限状態は `true` だったが、この実行環境ではWindowServerのシステムフォーカス取得が `-25204` で失敗した。

```text
accessibility-trusted=true
focused-application-error=-25204
focused-context=unavailable
```

この場合は、アプリ本体でも保存対象を作らず、既存の現在フォーカス入力へ戻る扱いにする。実際のログイン済みデスクトップ上でのユーザー操作による確認は、今回の自動実行環境からは完了できなかった。

### ディスプレイ接続後の再検証

前回の実行ではディスプレイが切断されていたため、ディスプレイ接続後に同じプローブを再実行した。`system_profiler` では、DELL S3423DWC がオンラインのメインディスプレイとして認識されていた。

実際のGUIセッションで、次の操作を3回連続して確認した。

1. システムワイドAccessibility APIから、現在のGoogle Chromeの対象ウィンドウを取得する。
2. Finderを一時的にアクティブ化する。
3. 保存したChromeアプリをアクティブ化し、保存したChromeウィンドウへ `kAXRaiseAction` を送る。
4. 復帰後のAccessibilityフォーカス対象とマウスポインタ位置を取得する。

3回とも次の結果になった。

```text
accessibility-trusted=true
original=app:Google Chrome pid:1393 window:ChatGPT - 構造化 Agent - Google Chrome
alternate-app=Finder pid:1412
alternate-activate=true
original-activate=true
original-raise=0
after=app:Google Chrome pid:1393 window:ChatGPT - 構造化 Agent - Google Chrome
mouse-before=(2658.0, 645.01953125)
mouse-after=(2658.0, 645.01953125)
```

この再検証により、ディスプレイ接続済みの実GUIセッションでは、システム全体の現在ウィンドウを取得し、別アプリを挟んだ後に元のウィンドウへ戻せることを確認できた。また、`activate` と `kAXRaiseAction` の実行によるマウスポインタの移動は観測されなかった。

なお、プローブ内の独立したシステムワイド属性読み出しは引き続き `-25204` を返したが、KotoTypeと同じ取得処理は直後にChromeの対象ウィンドウを正常に取得した。このため、単発の属性読み出しエラーだけでGUIセッション全体を利用不可とは判定せず、対象ウィンドウ取得と復帰後の対象一致を実際の成功条件として扱う。

### TextEditのウィンドウ取得と前面化

TextEditのAccessibilityアプリケーション要素を直接作成し、`kAXWindowsAttribute` から `AXWindow` を取得した。取得したウィンドウは標準ウィンドウで、識別子も取得できた。

```text
application=テキストエディット
window-role=AXWindow
window-subrole=AXStandardWindow
window-identifier=_NS:34
raise-action=success
```

`AXUIElementPerformAction(..., kAXRaiseAction)` は成功した。

### アプリのアクティブ化

`NSRunningApplication.activate(options: [])` もコンパイルでき、呼び出し結果は `true` だった。ただし、この自動実行環境では呼び出し直後も前面プロセスがTerminalのままで、戻り値だけでは前面化完了を保証できなかった。

そのため実装では、アプリのアクティブ化を試みた後に保存済みウィンドウへ `kAXRaiseAction` を送り、そのAccessibility操作が成功した場合だけ復帰成功と判定する。前面化できなければ、既存の現在フォーカス貼り付けへ戻る。

### マウスポインタへの影響

前面化処理の前後で `NSEvent.mouseLocation` を比較した。

```text
mouse-location=(660.0, 1098.01953125)
mouse-location-after-raise=(660.0, 1098.01953125)
```

前面化によって物理的なマウスポインタは移動しなかった。

### ウィンドウ同一性の判定

Accessibility要素のオブジェクト参照だけに依存すると、再取得時に同一性を安定して判定できないケースがあった。そのため実装では、プロセスIDに加えて、Accessibility APIから取得できる次の情報を使う。

- `AXIdentifier`
- `AXTitle`
- `AXRole` / `AXSubrole`
- `AXDocument`
- `AXPosition` / `AXSize`

安定した識別子がない場合に同一と断定せず、保存済みウィンドウの前面化を試す側へ倒している。これにより、別ウィンドウへ誤って貼り付ける危険を優先的に避ける。

## 実装結果

- 録音開始時に現在のAccessibilityフォーカス対象を保存する。
- 文字起こし完了時、保存対象と現在対象が一致すれば復帰処理を省略する。
- 異なる場合だけ、必要に応じて対象アプリをアクティブ化し、保存済みウィンドウへ `kAXRaiseAction` を送る。
- 取得・アクティブ化・前面化に失敗した場合は、現在の既存貼り付け処理へ戻す。
- Voice Shortcutのテキスト挿入・キーコマンドにも同じウィンドウ復帰を適用する。
- マウス移動APIやマウスイベントは追加していない。

## 検証

`WindowFocusRestorerTests` 6件で次を確認した。

- 同じウィンドウならアプリのアクティブ化・ウィンドウ前面化を呼ばない
- フォーカスが変わった場合は保存済みウィンドウを前面化する
- アプリのアクティブ化に失敗した場合は前面化しない
- ウィンドウ前面化に失敗した場合は `unavailable` を返す
- 識別情報が不足しているウィンドウを同一と誤判定しない

KotoType本体の音声入力から貼り付け完了までのE2E確認は、文字起こしサーバーとユーザー操作を伴うため、今回のAPIプローブとは別の確認項目としてPRレビュー時に実施する。

## 実装後の検証結果

```text
make build-app                       成功
swift test                           250 tests, 0 failures
swift test --filter WindowFocusRestorerTests  6 tests, 0 failures
git diff --check                     成功
```

このため、コード上の復帰条件、既存のSwiftテスト、およびディスプレイ接続済みGUIセッションでのOS API経路は確認できた。残る確認項目は、実際にKotoTypeを起動し、別アプリの別ウィンドウへ移動した状態から文字起こし結果が保存ウィンドウへ戻ることを、実ユーザー操作で確認することである。
