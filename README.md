# JsonUITestRunner for iOS

XCUITestベースのJsonUI用テストランナー。

## インストール

### Swift Package Manager

`Package.swift` に依存を追加:

```swift
dependencies: [
    .package(url: "https://github.com/Tai-Kimura/jsonui-test-runner", from: "1.0.0")
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
2. URLを入力: `https://github.com/Tai-Kimura/jsonui-test-runner`
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
    config.continueOnFailure = true  // 失敗しても続行
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

### ViewModel状態の検証

`state` アサーションを使うには、`ViewModelStateProvider` を実装:

```swift
class MyStateProvider: ViewModelStateProvider {
    let viewModel: LoginViewModel

    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    func getValue(at path: String) -> Any? {
        switch path {
        case "isLoading":
            return viewModel.isLoading
        case "email":
            return viewModel.email
        case "errorMessage":
            return viewModel.errorMessage
        default:
            return nil
        }
    }
}

// テストで使用
func testWithStateValidation() throws {
    let stateProvider = MyStateProvider(viewModel: viewModel)
    let runner = JsonUITest.createRunner(
        app: app,
        stateProvider: stateProvider
    )

    let test = try JsonUITest.loadFromBundle(name: "login.test")

    switch test {
    case .screen(let screenTest):
        let result = runner.run(screenTest: screenTest)
        XCTAssertTrue(result.allPassed)
    case .flow(let flowTest):
        let result = runner.run(flowTest: flowTest)
        XCTAssertTrue(result.allPassed)
    }
}
```

## テストJSONファイルの配置

1. テストJSONファイルを作成 (例: `login.test.json`)
2. UITestターゲットの "Build Phases" > "Copy Bundle Resources" に追加
3. テストコードで `Bundle(for: type(of: self))` を使って読み込み

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
