# JsonUITestRunner for iOS

XCUITestベースのJsonUI用テストランナー。

## インストール

### Swift Package Manager

`Package.swift` に依存を追加:

```swift
dependencies: [
    .package(url: "https://github.com/Tai-Kimura/jsonui-test-runner-ios", from: "1.0.0")
],
targets: [
    .testTarget(
        name: "YourAppUITests",
        dependencies: ["JsonUITestRunner"]
    )
]
```

または、Xcodeで:
1. File > Add Package Dependencies
2. URLを入力: `https://github.com/Tai-Kimura/jsonui-test-runner-ios`
3. UITestターゲットに追加

## 使い方

### 基本的な使い方

```swift
import XCTest
import JsonUITestRunner

class LoginUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testLoginScreen() throws {
        // テストJSONをバンドルから読み込み
        let result = try runJsonUITest(
            resourceName: "login.test",
            bundle: Bundle(for: type(of: self)),
            app: app
        )

        // 結果を確認
        XCTAssertTrue(result.allPassed, "Failed cases: \(result.failedCount)")
    }
}
```

### テストJSONをインラインで使用

```swift
func testWithInlineJSON() throws {
    let json = """
    {
        "type": "screen",
        "source": { "layout": "layouts/login.json" },
        "metadata": { "name": "login_test" },
        "cases": [
            {
                "name": "初期表示確認",
                "steps": [
                    { "assert": "visible", "id": "email_input" },
                    { "assert": "visible", "id": "password_input" }
                ]
            }
        ]
    }
    """.data(using: .utf8)!

    let result = try runJsonUITest(json: json, app: app)
    XCTAssertTrue(result.allPassed)
}
```

### カスタム設定

```swift
func testWithCustomConfig() throws {
    var config = TestRunnerConfig()
    config.screenshotOnFailure = true
    config.defaultTimeout = 10.0

    let result = try runJsonUITest(
        resourceName: "login.test",
        bundle: Bundle(for: type(of: self)),
        app: app,
        config: config
    )

    // 詳細な結果を確認
    for caseResult in result.caseResults {
        if !caseResult.passed {
            print("Failed: \(caseResult.name)")
            print("Error: \(caseResult.error?.localizedDescription ?? "Unknown")")
        }
    }
}
```

失敗した case があってもファイルは止まらず、後ろの case もすべて走る（Android / Web と同じ）。`skip` / platform / responsive で外れる case は従来どおり自分の skipped 行になる。teardown の失敗行を除けば、結果の行数はファイルの case 数と一致する。2.0.0 で `continueOnFailure` は設定ごと無くなった（それまでは既定 false で最初の失敗で止まり、残りを skipped 行にしていた）。設定していた利用側は、その行を消せば 2.0.0 で compile が通る。

flow の結果は 1 行で、`testName` は flow の `metadata.name`、`caseName` は常に `"flow"`（Android / Web と同じ。スクリーンショット等の artifact 名の case 部分も `flow`）。

### ViewModel状態の検証（`state`）と initialState

1.15.0 から、ハーネスは何も渡さなくてよい。SwiftJsonUI ≥ 10.30.0 と同じ列車の jsonui-cli で生成した画面は、
自分の Data を「state ブリッジ」（アクセシビリティ要素 `__state_<screenId>` の value）に出す。
`state` アサーションと `when.state` は、既定でその `data` を path でたどる。

- 読む画面: screen test はテスト対象画面（`source.layout` の screen id）。flow は step の `screen`、無ければ直前に名前が出た画面。flow から参照した case は、参照先ファイルの画面。
- ブリッジが無い（画面がまだ出ていない、またはライブラリが古い）ときは auto-wait の中で待ち、timeout でその理由を出す。32KB を超えたブリッジ（`{"truncated": …}`）は即失敗する。
- アプリのプロセスはテストランナーと別なので、ViewModel を直接読む provider は書けない。それでも独自の provider を渡したい場合は、`createRunner(app:stateProvider:)` で渡せば、そちらを優先する。

`initialState`（ファイル単位、case 単位は `caseIsolation: "reopen"` のとき、flow は `viewModels`）は、起動時に launch environment `JSONUI_TEST_INITIAL_STATE` で渡る。
画面が最初に表示されたときに一度だけ Data に入り、ブリッジに受領（applied / rejected）が出る。
runner は `screenReadyTimeout`（既定 15 秒）のあいだ受領を待つ。受領が無い、または rejected がある場合は、その case を `setup` の失敗にする。
キーは Data 名だけ、値は Data の class に合う JSON だけが入る（仕様: jsonui-test-runner `specs/2026-07-08-advanced-test-features.md` §10）。

```swift
var config = TestRunnerConfig()
config.screenReadyTimeout = 20.0   // 受領を待つ時間（既定 15 秒）
```

### 起動の環境変数（runner が持つキー）

runner は `JSONUI_TEST_CLEAR_STATE` / `JSONUI_TEST_ARGS` / `JSONUI_TEST_PERMISSIONS` / `JSONUI_TEST_INITIAL_STATE` の 4 つを持つ。
起動のたびに 4 つとも消してから、その起動の分を設定し直す。前のファイルの `launch` は次のファイルの起動に残らない。
ハーネスが自分で `app.launchEnvironment` に入れたほかのキーには触らない。

### 進捗レコード（`jui viz` が読む）

runner は実行中の進捗を 1 行 1 JSON（jsonui-test-runner `schemas/progress.schema.json`）で unified logging に出す。
subsystem `com.jsonui.testrunner`、category `progress`、info、public。常に出る（verbose とは無関係）。出力の失敗は結果を変えない。

```bash
xcrun simctl spawn <udid> log stream --style ndjson --level info \
  --predicate 'subsystem == "com.jsonui.testrunner" AND category == "progress"'
```

- `run(screenTest:)` / `run(flowTest:)` の 1 回が 1 run（`run_start` … `run_end`）。`run_end` の件数は results.json と同じ数え方。
- case は試行ごとに `case_start` / `case_end`（`attempt` 1, 2, …）。実行されなかった case は `attempt: 0` の `case_end`（skipped）1 行だけ。setup や起動の失敗の行、`teardown` の行も 1 組出る。
- `test` / `case` は results.json の testName / caseName と同じ。`file` は `TestLoader` が読んだファイルの、読んだ root（bundle の resources、`loadAll` のディレクトリ）からの相対パス。コードで組んだテストや inline JSON は `"inline"`。

### 結果ファイル（`resultsPath` と既定の置き場所）

`config.resultsPath` を設定すると、従来どおりそのパスに results JSON（jsonui-test-runner `schemas/results.schema.json`）を書く。run のたびに同じファイルを上書きし、キーも従来と同じ（`run` / `app` / `file` は足さない）。このとき既定の置き場所には何も書かない。

`resultsPath` を設定しないときは、run（`run(screenTest:)` / `run(flowTest:)` の 1 回）ごとに新しいファイルを 1 本、既定のフォルダに書く。古い run のファイルは上書きしない。`jui viz` が過去の run として読む。

```
<base>/ios/<app>/<UTC yyyyMMdd'T'HHmmss.SSS'Z'>-<run>-<fileKey8>.json
```

- `<base>`: ホストの `$JSONUI_TEST_RESULTS_DIR`（絶対パスのときだけ）、無ければ `~/.local/state/jsonui-test/results`（ホームはシミュレータが渡す `SIMULATOR_HOST_HOME`）。`XDG_STATE_HOME` は見ない（シミュレータからホストの値が見えないため）。
- `JSONUI_TEST_RESULTS_DIR` はホスト側の変数。iOS ではテストプロセスに届かないので、xcodebuild に `TEST_RUNNER_` を付けて渡す: `TEST_RUNNER_JSONUI_TEST_RESULTS_DIR=/abs/path xcodebuild test …`。Android の端末側には効かない（端末内の固定の場所に書く）。
- `<app>`: UI テストランナーの bundle id（`<UITest の bundle id>.xctrunner`）。`[A-Za-z0-9._-]` 以外の文字は `_` に置き換える。ファイルの中の `"app"` は置き換える前の値。
- `<run>`: その run の進捗レコードと同じ run id。ファイルには既存の内容に加えて、トップレベルの `"run"` / `"app"` と `suites[0].file`（進捗レコードの `file` と同じ文字列）が入る。
- 書き込みは同じフォルダの `.<name>.tmp` に書いてから rename する（読み手が書きかけのファイルを見ることはない）。
- `<fileKey8>` は、その run のテストファイル（`suites[0].file`）の UTF-8 の SHA-256 の先頭 8 桁。名前だけで、どのテストファイルの結果かが分かる。
- 書いた後、そのアプリのフォルダだけを整理する: **テストファイルごとの最新の 1 本は常に残す**（何日たっても、ほかのファイルを何回流しても消えない）。14 日と 500 本の規則は、それより新しい同じテストファイルの結果に置き換えられた古いもの（と、ファイル鍵の無い前の形の名前 `<時刻>-<run>.json`）にだけ当てる。形の合わないファイル、サブフォルダ、他のアプリのフォルダには触らない。規則と検体は jsonui-test-runner の `specs/vectors/results-prune.json`（3 つのドライバーと `jui viz` が写しを持つ）。
- 実機は対象外: シミュレータでないとき（または `SIMULATOR_HOST_HOME` が無いとき）は何も書かない。
- 書き込みの失敗はテストの結果を変えない。失敗の種類ごとにプロセスで 1 回だけ注意を出す。

## テストJSONファイルの配置

1. テストJSONファイルを作成 (例: `login.test.json`)
2. UITestターゲットの "Build Phases" > "Copy Bundle Resources" に追加
3. テストコードで `Bundle(for: type(of: self))` を使って読み込み

`TestLoader.loadAll(from:)`（`loadAllFromBundle` も同じ）は対象の `*.test.*.json` を全部試し、読めないファイルが 1 本でもあれば、失敗したパスと理由を全部並べたエラー（`TestLoaderError.unreadableFiles`）を 1 回だけ throw する。警告を出して飛ばすことはしない。

## 要素の特定

JsonUIの `id` 属性が `accessibilityIdentifier` としてマッピングされます:

```json
// Layout JSON
{
  "class": "TextField",
  "id": "email_input",
  "properties": { ... }
}
```

```json
// Test JSON
{ "action": "tap", "id": "email_input" }
```

## 対応アクション

| アクション | 説明 |
|-----------|------|
| `tap` | タップ |
| `doubleTap` | ダブルタップ |
| `longPress` | 長押し |
| `input` | テキスト入力 |
| `clear` | 入力クリア |
| `scroll` | スクロール |
| `swipe` | スワイプ |
| `waitFor` | 要素出現待機 |
| `wait` | 固定時間待機 |
| `back` | 戻る |
| `screenshot` | スクリーンショット |

## 対応アサーション

| アサーション | 説明 |
|-------------|------|
| `visible` | 表示確認 |
| `notVisible` | 非表示確認 |
| `enabled` | 有効確認 |
| `disabled` | 無効確認 |
| `text` | テキスト検証 |
| `count` | 要素数検証 |
| `state` | ViewModel状態検証 |

## API モック

`jsonui-test mock serve` のモックサーバーに向けて、空状態・エラー状態を決定的にテストできます。
アプリの向き先は `launch.arguments.apiBase` で差し替え、ランナーにサーバー URL とトークンを渡します:

```swift
var config = TestRunnerConfig()
config.mockServerURL = URL(string: "http://localhost:8790")
config.mockToken = ProcessInfo.processInfo.environment["JSONUI_MOCK_TOKEN"]
```

- screen テストの root `mocks`（例: `{"listStocks": "empty"}`）は、ケース実行前に
  シナリオを設定してアプリを再起動してから適用されます（シナリオはファイル単位。
  正常/空/エラーは別ファイルに分割）。
- flow テストでは `setMocks` ステップで遷移途中にシナリオを切り替えます（次の遷移で再 fetch）。
- 各実行の終了時にシナリオは `default` にリセットされます。
