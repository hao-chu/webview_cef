# 使用本機 CEF 149.0.6 套件的建置分析

分析日期：2026-11-03。主要範圍為 Flutter Linux 桌面、x86_64；eLinux 另列限制。本次產出分析文件與可套用的 patch，尚未將 patch 套用到工作區的正式程式，也沒有準備正式的 `third/cef`。

## 結論

可以採用這份套件。專案目前固定使用 **CEF 149.0.4 / Chromium 149.0.7827.156**，目標為 **CEF 149.0.6 / Chromium 149.0.7827.201**，屬於同主版本修正更新。實際以新套件驗證，現有 Linux／共用原始碼可編譯，wrapper 可重建，Linux 外掛可連結新 `libcef.so`。

完成正式建置仍須處理三件事：

1. 同步 CEF 版本設定與本機解壓內容，讓現有準備流程直接使用本機套件。
2. 這份套件只有 `Release/`；若要支援 Flutter Debug／Profile，必須讓連結與打包都選用 CEF Release runtime，並確認 plugin／wrapper 的編譯定義一致。
3. 修正 example 現有的多檔案安裝規則，讓最終 bundle 能完成安裝。

另外，這份套件的二進位檔需要 **GLIBC_2.38** 符號。目標系統必須提供這些符號及其他動態相依庫；這項結果只適用於本次檢查的套件，不能推廣為所有 CEF 149 發行包的最低要求。

## 可套用的 patch

已產生 [`patches/cef-149.0.6-linux.patch`](patches/cef-149.0.6-linux.patch)，以目前外掛原始碼為基準，包含三個檔案：

| 檔案 | patch 的更新 |
| --- | --- |
| `third/download.cmake` | 更新共用 CEF 版本；優先使用外掛根目錄、檔名相符的本機套件，沒有本機套件時沿用 CDN；檢查下載、解壓、必要檔案、版本與架構準備結果，全部成功才寫入版本標記 |
| `linux/CMakeLists.txt` | Debug／Profile／Release 均使用 CEF Release runtime；同步打包目錄與 Profile wrapper 的 `NDEBUG` |
| `example/linux/CMakeLists.txt` | 修正多檔案安裝清單的外層引號 |

舊版 CEF 的解壓內容直接重新準備，不做備份；使用者提供的本機 `.tar.bz2` 會保留。CDN 下載的 `prebuilt.zip` 暫存檔在成功解壓後刪除。共用版本固定值也會影響其他平台之後要求的 CEF 版本；此 patch 的原生建置驗證限 Linux x86_64。

從獨立的 `webview_cef` 儲存庫根目錄檢查並套用：

```bash
git apply --check docs/patches/cef-149.0.6-linux.patch
git apply docs/patches/cef-149.0.6-linux.patch
```

若外掛放在另一個 app 儲存庫的 `packages/webview_cef`，先把 patch 存到已知位置，再從該 app 儲存庫根目錄執行：

```bash
git apply --check --directory=packages/webview_cef /path/to/cef-149.0.6-linux.patch
git apply --directory=packages/webview_cef /path/to/cef-149.0.6-linux.patch
```

外掛副本須保有此 patch 修改的三個檔案，包括 `example/linux/CMakeLists.txt`。patch 修正的是外掛內的 example；目標 app 若有同樣的安裝清單錯誤，仍需依下方整合步驟調整該 app 自己的 CMake。

套用後，將以下套件放在外掛根目錄，與外掛 `pubspec.yaml` 同層：

```text
cef_binary_149.0.6+g0d0eeb6+chromium-149.0.7827.201_linux64.tar.bz2
```

接著從引用該外掛的 app 執行建置。patch 會自動解壓並產生 `third/cef/version.txt`，不需要另做下方的手動解壓及標記步驟。壓縮檔本身不包含在 patch 中；其他電腦或 CI 也須備妥相同套件，否則會走 CDN 下載流程。

### Patch 驗證範圍

patch 已在隔離副本實際套用後驗證，沒有直接修改工作區的三個正式原始檔：

- `git apply --check` 通過；套用後三個檔案與預期內容一致。
- 8 項準備流程檢查通過：本機優先且保留原檔、相同版本重複跳過、模擬下載分支與暫存清理、損壞套件、缺少必要檔案、版本不符、架構準備失敗及下載失敗。測試路徑均含空白；錯誤案例均確認未寫入成功標記。
- Release／Debug／Profile 均確認使用 C++20、Release CEF runtime，以及一致的 plugin／wrapper `NDEBUG` 定義。
- 三種模式的 Linux 原生編譯、連結與 example CMake 安裝規則均通過；各 bundle 的 15 個檢查路徑存在，並包含 228 個 locale `.pak`。
- 各模式的 example、plugin、`libcef.so` 皆以 `ldd` 確認本機沒有缺少的函式庫；既有 Linux runner 修改器測試通過。

這次原生整合使用套用 patch 後的 plugin 與 example CMake，實際經過本機套件自動準備與安裝流程；Flutter 產生的建置規則改用測試替身，連結既有 `/opt/flutter` 3.38.3 engine，Dart assets／AOT 安裝項目則使用明確的測試資料。這不代表已執行完整 `flutter build`，也未執行 Flutter 3.41.9、`flutter analyze`、Dart tests 或 GUI 功能驗證。套用到目標 app 後，仍須完成下方列出的正式驗收。

驗證腳本為 `/tmp/cef149-patch-2z94xp3v/validate_prepare.py`，完整記錄位於 `/tmp/cef149-patch-2z94xp3v/logs/`；三種模式分別保留 `*-configure.log`、`*-build.log`、`*-install.log`、`*-compile-evidence.json` 與 `*-ldd.log`。這些是本機暫存診斷，不包含在 patch 中。

## 本機證據

| 項目 | 實際結果 |
| --- | --- |
| 現有版本 | `third/download.cmake:5`：`149.0.4+g2f1bfd8+chromium-149.0.7827.156` |
| 已安裝 CEF | `third/cef` 目前只有受版本控制的 `.gitignore`，尚無已解壓 runtime |
| 目標套件 | 工作目錄中的 `cef_binary_149.0.6+g0d0eeb6+chromium-149.0.7827.201_linux64.tar.bz2` |
| 套件內版本 | `README.txt`、`include/cef_version.h` 均為題目指定版本 |
| CEF commit | `0d0eeb61160536e447c79335c1ee963f57eb6d60` |
| Runtime | `Release/` 有全部 8 個 CMake 列出的 binary 檔案；沒有 `Debug/`、`Profile/` |
| Resources | 5 個資源項目均存在，其中 `locales/` 有 228 個 `.pak` |
| C++ 標準 | 套件的 `cmake/cef_variables.cmake` 使用 `-std=c++20`；專案 Linux 已設 C++20 |
| 主機 | x86_64、glibc 2.39、Clang 18.1.3、CMake 3.28.3 |
| Flutter | `.fvmrc` 指定 3.41.9，但該 SDK 尚無 engine artifacts；隔離原生驗證使用既有 `/opt/flutter` 3.38.3 的 Linux 標頭與函式庫 |

本機檔案 SHA-256：

```text
8c08027eb656776c542e1f0f81817230969f9e44511fa3961fab0b1c35fdcbd0
```

此雜湊用於識別本次分析的檔案，尚未與發行端提供的可信校驗值比對。官方網站查核未能讀取此精確版本的下載列項；版本與內容的直接證據來自本機套件。

## 現有流程與需要修改的位置

### 1. 版本固定與本機套件

[`third/download.cmake`](../third/download.cmake) 依平台及架構組出檔名，再由 `prepare_prebuilt_files()` 檢查 `third/cef/version.txt`。

原始流程**不會自動尋找根目錄的 `.tar.bz2`**。若目錄缺少版本標記，或標記內容與預期檔名不同，就會移除既有 CEF 子目錄並走下載流程。因此，只把新套件解壓進 `third/cef`，下一次 configure 仍可能被目前的 149.0.4 設定覆蓋。上方 patch 已加入本機套件自動準備；本節的手動做法供未使用 patch 時參考。

最小做法是修改既有固定值：

```cmake
set(CEF_VERSION "149.0.6+g0d0eeb6+chromium-149.0.7827.201")
```

這是共用版本設定，也會改變 Windows、macOS、Linux ARM64 之後預期的下載版本。本次沒有驗證那些平台對應的新發行包或建置結果。若需求僅限 Linux，實作時應先確認是否接受這個共用版本變動。

接著使用已提供的本機檔案。以下為待實作步驟，未在正式目錄執行。CEF 是可重複下載的資源，不需備份舊版；若已有其他版本，先清除其解壓內容，再準備新套件，避免混用版本。

```bash
# Run from the repository root, after updating CEF_VERSION.
set -euo pipefail
archive="cef_binary_149.0.6+g0d0eeb6+chromium-149.0.7827.201_linux64.tar.bz2"
mkdir -p third/cef
tar -xjf "$archive" --strip-components=1 -C third/cef

# Write this only after extraction and required-file checks succeed.
for file in include/cef_version.h cmake/FindCEF.cmake libcef_dll/CMakeLists.txt \
  Release/libcef.so Release/v8_context_snapshot.bin Resources/icudtl.dat; do
  test -f "third/cef/$file"
done
test -d third/cef/Resources/locales
printf '%s' "$archive" > third/cef/version.txt
```

`--strip-components=1` 去掉套件最外層目錄，使路徑成為 `third/cef/include`、`third/cef/Release` 等。版本標記必須是**完整檔名且沒有結尾換行**，因為現有程式用 `file(READ)` 直接比較字串。這樣 configure 才會走「No need to update」，不必重新下載 CEF。

若未來需要 CI 自動從任意本機路徑準備套件，再考慮新增 archive 路徑參數；本次單次替換不必先增加這層設定。

### 2. Debug／Profile 的連結與打包

[`linux/CMakeLists.txt:89`](../linux/CMakeLists.txt#L89) 現在將 Debug 連到 `CEF_LIB_DEBUG`；資源清單又使用 `CEF_BINARY_DIR`。新套件內的 CMake 設定如下：

```cmake
set(CEF_BINARY_DIR "${_CEF_ROOT}/${CMAKE_BUILD_TYPE}")
set(CEF_LIB_DEBUG "${_CEF_ROOT}/Debug/libcef.so")
set(CEF_LIB_RELEASE "${_CEF_ROOT}/Release/libcef.so")
```

因此各建置模式的狀態不同：

| Flutter 模式 | 現有設定與這份套件搭配的結果 | 處理方式 |
| --- | --- | --- |
| Release | binary／resource 路徑均有對應檔案 | 可作為第一個正式建置目標 |
| Debug | `Debug/libcef.so` 與其餘 Debug binary 不存在 | 連結、打包都改用 Release runtime |
| Profile | `Profile/` 不存在，打包清單指向無效路徑 | 明確映射 Release，並使用 Release 打包目錄 |

建議沿用專案 Windows 已採用的作法，讓所有 Flutter 模式使用 CEF Release runtime。在 Linux 原本建立 `libcef_lib` 的位置改為：

```cmake
ADD_LOGICAL_TARGET("libcef_lib" "${CEF_LIB_RELEASE}" "${CEF_LIB_RELEASE}")
set_target_properties(libcef_lib PROPERTIES MAP_IMPORTED_CONFIG_PROFILE Release)
set(CEF_BINARY_DIR "${CEF_BINARY_DIR_RELEASE}")
```

最後一行必須位於組合 `cef_library_list` 之前。只改連結位置仍會讓打包尋找不存在的 Debug／Profile 檔案。

`libcef_dll_wrapper` 繼續由新套件的 `libcef_dll/` 原始碼建置，並與 plugin 保持一致的編譯模式和 API 設定。不要重用舊版 wrapper，也不要為了選用 Release runtime 而單獨強制 wrapper 使用不同的編譯模式。本次實測的是 Release plugin／Release wrapper；Debug／Profile 仍須各自完整驗證。

Profile 還有一項既有定義差異：example 的 `apply_standard_settings()` 會對非 Debug plugin 加入 `NDEBUG`，但套件巨集只對 Release wrapper 加入該定義。本次以 Profile configure 的 `compile_commands.json` 證實，plugin 有 `-DNDEBUG`、wrapper 沒有。CEF 的 `DCHECK_IS_ON()` 會影響部分共用型別布局，因此不能只完成 runtime 映射就視為 Profile 已可用。最小修改是在 `add_subdirectory(... libcef_dll_wrapper)` 之後補入：

```cmake
target_compile_definitions(libcef_dll_wrapper PRIVATE "$<$<CONFIG:Profile>:NDEBUG>")
```

這是針對本專案 example 的編譯設定；實際宿主若客製編譯定義，仍須確認兩個 target 一致。此項尚未執行完整 Profile 建置或執行測試。

### 3. Example 的 bundle 安裝

[`example/linux/CMakeLists.txt:135`](../example/linux/CMakeLists.txt#L135) 現在使用：

```cmake
install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
```

外層引號會把分號分隔的檔案清單當成單一路徑，而 CEF 外掛會提供多個 binary 與 resource。本次用兩個小檔案、相同的 CMake 安裝寫法重現 `file INSTALL cannot find ".../a.txt;.../b.txt"`，可確認此清單用法有問題；完整 Flutter 安裝流程尚未執行。

最小修正是讓 FILES 接收展開的清單：

```cmake
install(FILES ${PLUGIN_BUNDLED_LIBRARIES}
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
```

既有 `if(PLUGIN_BUNDLED_LIBRARIES)` 防護可保留。`locales/` 維持由 plugin 的目錄安裝規則處理。本次只是列出修改方向，尚未變更正式 CMake。

### 4. API 與啟動流程

現有 `common/*.cc` 共 6 個檔案及 `linux/webview_cef_plugin.cc`，已用新標頭通過 C++20 語法檢查；同一組檔案也通過隔離 Release 編譯與連結。目前沒有證據顯示本次更新需要修改 Dart API 或 CEF callback 簽章。

現有流程可保留：

- `example/linux/main.cc` 在 GTK 啟動前呼叫 `initCEFProcesses()`，並回傳非負子行程退出碼。
- `common/webview_plugin.cc` 呼叫 `CefExecuteProcess()`，啟用 windowless rendering，並在 Linux 使用 `multi_threaded_message_loop`。
- `common/webview_handler.cc` 呼叫 `SetAsWindowless(0)`，Linux 透過 `OnPaint` 更新 Flutter texture。

精確版 Linux 標頭確認 `SetAsWindowless()` 會設定 `CEF_RUNTIME_STYLE_ALLOY`。這是 runtime **style**；不應加入舊文件提及的 `CefSettings.chrome_runtime`，因為此套件的 settings 已無該欄位。

套件預設 `CEF_API_VERSION` 為 experimental API，現有專案沒有另外固定 API 版本。本次最小替換維持原設定，讓 plugin、wrapper、headers、`libcef.so` 全部來自同一發行包；沒有必要另外引入 API versioning 改造。

## Bundle 與執行環境

沿用現有 Linux 安裝規則，完成後應有以下配置：

```text
bundle/
  example
  data/
  lib/
    libwebview_cef_plugin.so
    libcef.so
    libEGL.so
    libGLESv2.so
    libvk_swiftshader.so
    libvulkan.so.1
    vk_swiftshader_icd.json
    v8_context_snapshot.bin
    chrome-sandbox
    icudtl.dat
    chrome_100_percent.pak
    chrome_200_percent.pak
    resources.pak
    locales/*.pak
```

不要只換 `libcef.so`。現有 CMake 已依 CEF 提供的清單處理 binary 與 resources，應保留這條路徑，並在正式安裝後確認 `locales/` 及所有資源仍存在。套件 README 將 `libcef.so`、`icudtl.dat`、`v8_context_snapshot.bin` 列為必要元件；其他檔案會影響語系、畫面資源或繪圖功能。

本次以 `readelf --version-info` 檢查，`libcef.so`、EGL／GLES、Vulkan／SwiftShader、`chrome-sandbox` 均需要 `GLIBC_2.38`；`libcef.so` 的實例包括 `__isoc23_strtol@GLIBC_2.38`。這是 loader 層的限制，修改 C++ 標準或重編 wrapper 無法消除。主機 glibc 2.39 的 `ldd` 檢查未發現缺少的相依庫，但部署機仍須另行驗證，且 plugin／Flutter 也有各自的 runtime 需求。

## 整合到其他 Flutter app

建議將修改後的 `webview_cef` 作為 app 的本機 path dependency。CEF 的版本、解壓內容、wrapper 與 Linux 連結設定都由外掛管理；app 負責引用外掛、runner 整合與最終 bundle 安裝。以下是待執行的整合步驟，本次沒有修改或建置其他 app。

### 1. 將外掛放入目標 app

目錄配置例如：

```text
my_app/
  pubspec.yaml
  lib/
  linux/
  packages/
    webview_cef/
      pubspec.yaml
      lib/
      common/
      linux/
      third/
```

複製完整的外掛原始碼，保留根目錄 `pubspec.yaml` 與平台設定；上圖只列出本次整合相關目錄。將目標 app 原有的 `webview_cef` 相依改為：

```yaml
dependencies:
  flutter:
    sdk: flutter
  webview_cef:
    path: packages/webview_cef
```

`path` 指向外掛的根目錄，相對於 app 的 `pubspec.yaml`。這是 Dart 官方支援的本機套件引用方式，參見 [Path packages](https://dart.dev/tools/pub/dependencies#path-packages)。也可以將外掛放在 app 外部，使用如 `../webview_cef` 的相對路徑；其他建置機必須具有相同的相對目錄配置。

目標 app 的 Flutter／Dart 版本須符合外掛 `pubspec.yaml`：Flutter >= 3.27.0、Dart >= 3.6.0 且 < 4.0.0。原生工具鏈須支援 C++20，部署機須符合前述 x86_64、GLIBC_2.38 符號及動態相依庫要求。

### 2. 在外掛內套用前述 CEF 修改

目前正式程式尚未套用升級，僅複製這份原始碼仍會使用原有的 149.0.4 設定。請在目標 app 的外掛副本中，套用「現有流程與需要修改的位置」所列修改：

| 外掛內的檔案 | 必要變更 |
| --- | --- |
| `third/download.cmake` | 將 `CEF_VERSION` 設為 `149.0.6+g0d0eeb6+chromium-149.0.7827.201` |
| `linux/CMakeLists.txt` | 將 `libcef_lib` 的 Debug／Release 都指向 `CEF_LIB_RELEASE`，明確設定 Profile 映射，並將 `CEF_BINARY_DIR` 指向 `CEF_BINARY_DIR_RELEASE` |
| `linux/CMakeLists.txt` | 建立 wrapper 後，依宿主編譯設定補齊 Profile 的 `NDEBUG`，確認 plugin／wrapper 定義一致 |

具體 CMake 程式碼見前述「Debug／Profile 的連結與打包」。Linux 外掛已宣告 C++20，目標 app 的自訂規則須避免將外掛強制降為較舊標準。共用 `CEF_VERSION` 變動仍會影響其他平台的預期版本。

### 3. 在外掛副本內準備本機 CEF

若已經有其他版本，先清除舊版 CEF 的解壓內容，再準備新套件，不需備份。以下從 `my_app/packages/webview_cef` 執行；將 `archive_dir` 換成壓縮檔實際存放位置：

```bash
set -euo pipefail
archive_dir="/你的套件存放路徑"
archive="cef_binary_149.0.6+g0d0eeb6+chromium-149.0.7827.201_linux64.tar.bz2"
mkdir -p third/cef
tar -xjf "$archive_dir/$archive" --strip-components=1 -C third/cef

for file in include/cef_version.h cmake/FindCEF.cmake libcef_dll/CMakeLists.txt \
  Release/libcef.so Release/v8_context_snapshot.bin Resources/icudtl.dat; do
  test -f "third/cef/$file"
done
test -d third/cef/Resources/locales
printf '%s' "$archive" > third/cef/version.txt
```

解壓及版本設定一致時，外掛的準備流程才會直接使用本機 CEF。手動解壓的原始 `.tar.bz2` 會保留；原始下載流程使用的 `prebuilt.zip` 則會在解壓後刪除。另一台電腦或 CI 需要取得相同套件並重做準備，path dependency 本身不會替它準備本機 CEF。

### 4. 確認 app 的 runner 與 bundle 安裝

保留 app 原有的 Flutter plugin 載入與安裝流程。app 的 `linux/CMakeLists.txt` 若已使用 Flutter 標準的逐項安裝方式，可直接保留；若使用前述帶有清單外層引號的寫法，改為：

```cmake
install(FILES ${PLUGIN_BUNDLED_LIBRARIES}
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
```

不需要將本專案的 `example/linux/CMakeLists.txt` 整份覆蓋到目標 app；應保留該 app 的執行檔名稱、application ID 與自訂設定。

外掛 configure 會執行 `linux/target_modifier/modify_target.sh`，支援 `linux/runner/` 與舊版 `linux/` 兩種標準 runner 路徑，加入 CEF 初始化及鍵盤事件處理。完成後應確認 `main.cc` 已引入 `webview_cef/webview_cef_plugin.h`，並在 GTK 啟動前處理子行程退出碼：

```cpp
int exit_code = initCEFProcesses(argc, argv);
if (exit_code >= 0) {
  return exit_code;
}
```

若 app 已客製 runner，來源結構可能不符合修改腳本的預期，需依實際程式調整腳本或 hook 並驗證；不能只補上 `main()` 呼叫就視為鍵盤整合完成。Dart 端沿用 `WebviewManager`／`WebViewController`，在建立瀏覽器前完成一次 `WebviewManager().initialize()`。

### 5. 從目標 app 建置及驗證

在 SDK 與既有專案相依備妥後，從 `my_app` 根目錄執行：

```bash
flutter pub get
flutter analyze
flutter build linux --release
ldd build/linux/x64/release/bundle/lib/libcef.so
ldd build/linux/x64/release/bundle/lib/libwebview_cef_plugin.so
```

若 app 使用 FVM，以上所有 `flutter` 命令一致改用 `fvm flutter`。首次整合或更換 CEF 時，應清除既有建置快取後完整重建原生部分，或使用新的建置目錄，不需備份舊產物；hot reload 不會套用 CMake 或原生函式庫變更。

先確認 Release 完整建置與安裝，再分別驗證所需的 Debug／Profile。檢查最終 bundle 具有前述所有 CEF binary、resources 與 `locales/`，且 `ldd` 沒有缺少的函式庫。部署時提供整個 `bundle` 目錄，並在實際部署環境測試畫面、JS 橋接、cookies、輸入法、子行程及退出／重啟。

這些是其他 app 的待驗證步驟；本次已通過的隔離原生驗證，不能代替目標 app 的完整 Flutter 建置與功能測試。

## eLinux 與其他架構

- `linux64` 僅供 x86_64，不能替代 ARM64 發行包。
- `elinux/CMakeLists.txt` 仍宣告 C++17；若納入此次實作，應同步宣告 C++20，並驗證實際編譯參數。套件巨集本身也會加入 `-std=c++20`，所以不能僅憑宣告為 17 就斷定目前一定編譯失敗。
- eLinux 同樣有 Debug／Profile runtime 選擇問題。
- 這份 `libcef.so` 的直接相依包含 X11、Xcomposite、Xdamage、Xrandr、xcb、GBM 等。移除 plugin 的 GTK 使用不代表此預編譯 CEF 可直接用於沒有這些函式庫的精簡系統。
- 本次沒有驗證 eLinux 的 Wayland／DRM-GBM 顯示、輸入或跨架構建置；Linux 桌面原生連結成功不能視為 eLinux 驗收。

## 產生 patch 前的分析驗證

本節記錄初次分析時的驗證結果，尚未包含後續 patch；最新結果以前方「Patch 驗證範圍」為準。下表的待修正與未驗證狀態，是初次分析當時的狀態。

初次分析的解壓與原生驗證位於 `/tmp/webview-cef149-analysis`，使用已存在的工具與 SDK；沒有下載、安裝或升級額外工具，也沒有觸發 CEF 下載。

| 檢查 | 結果與範圍 |
| --- | --- |
| 完整 archive 列表與 metadata | 通過；確認版本、架構、Release-only 配置及資源清單 |
| 7 個 C++ 檔案語法檢查 | 通過；Clang 18、C++20、`-Wall -Werror`、新 CEF 標頭 |
| 官方 `libcef_dll_wrapper` Release 建置 | 通過；211 個 Ninja 步驟，產出靜態函式庫 |
| 原生 plugin 隔離 Release 建置 | 通過；7 個原始檔與新 wrapper／`libcef.so` 連結，啟用 `--no-undefined` |
| CEF／原生 plugin 的 `ldd` | 通過；本機沒有 `not found` |
| Linux runner 修改器既有測試 | 通過；`bash linux/target_modifier/tests/modify_target_test.sh` |
| Profile 編譯定義檢查 | configure 通過；確認 plugin 有 `NDEBUG`、wrapper 沒有，列為待修正差異 |
| 多檔案安裝最小案例 | 成功重現預期的安裝失敗；未修改重試，未聲稱正式 Flutter 安裝已實測 |
| 完整 Flutter Release／Debug／Profile 建置 | 未執行；正式版本設定尚未修改，隔離原生建置不涵蓋 Flutter assets、Dart AOT 或 bundle 安裝 |
| `flutter analyze`／Dart tests | 未執行；本次沒有修改 Dart 或正式建置程式 |
| GUI 功能、子行程與退出 | 未執行；環境沒有 DISPLAY，也沒有既有 Xvfb |

初次分析的 CMake 探針使用新套件的官方巨集及原有專案原始碼，但未直接執行 Flutter 的完整 CMake 入口，也未驗證正式套件準備流程。

重現原生建置：

```bash
cmake -S /tmp/webview-cef149-analysis/wrapper-check \
  -B /tmp/webview-cef149-analysis/wrapper-release -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
cmake --build /tmp/webview-cef149-analysis/wrapper-release \
  --target cef_plugin_probe --parallel 4
```

完整診斷保留於 `/tmp/webview-cef149-analysis/logs/`：`*.syntax.log`、`wrapper-configure.log`、`wrapper-build.log`、`plugin-configure.log`、`plugin-build.log`、`libcef-version-info.log`、`libcef-glibc238-symbols.log`、`libcef-ldd.log`、`plugin-ldd.log`、`runner-modifier-test.log`、`profile-configure.log`、`profile-ndebug-evidence.json`、`bundle-list-repro.log`。完整套件列表為 `/tmp/webview-cef149-archive-list.txt`。

## 正式實作的驗收順序

1. 確認部署機架構與 glibc 符號滿足需求，再同步版本、解壓內容與無換行的版本標記。
2. 修正 example 的多檔案安裝清單。若只需 Release，先驗證 Release；若要支援 `flutter run` 或 Profile，加入前述 runtime 映射，並同步驗證打包路徑與 plugin／wrapper 定義。
3. 使用一致的 Flutter SDK 建置。`.fvmrc` 指向的 3.41.9 尚缺 engine artifacts；補齊這些工具元件前須依使用者政策取得下載授權。本次不自行切換專案 SDK。
4. 在相依與 SDK 元件備妥後，從 `example/` 執行 `flutter build linux --release`，並另驗證 Debug／Profile；先清除既有建置快取或使用新的建置目錄，確保 wrapper 沒有沿用舊版。
5. 執行專案既有 runner 測試、plugin／example 的 `flutter analyze`，以及適用的既有 Dart tests。檢查最終 bundle 資源與 `ldd`。
6. 在有顯示環境的部署機驗證載入網頁、JS 雙向橋接、cookies、多 WebView、輸入法、縮放、子行程啟動、關閉及重啟。`CefInitialize` 結果及實際畫面須列入觀察；目前程式未檢查該回傳值。

若需回復版本，將版本設定改回目標版本，重新下載或解壓該版 CEF，並重新建置 wrapper 與 app；不需保留舊 CEF 或建置產物的備份。

## 第一方參考來源

本次精確版本事實優先依據壓縮檔內的 `README.txt`、`include/cef_version.h`、`include/cef_api_hash.h`、`include/internal/cef_linux.h`、`include/internal/cef_types.h` 與 `cmake/cef_variables.cmake`。以下官方文件供理解整合方式，不以現行 master 取代精確版套件證據。

- [CEF 官方版本與建置說明](https://github.com/chromiumembedded/cef/blob/master/docs/branches_and_building.md)：版本格式及建置流程。
- [CEF 官方 API versioning](https://github.com/chromiumembedded/cef/blob/master/docs/api_versioning.md)：API version 與相容性機制。
- [CEF 官方架構說明](https://github.com/chromiumembedded/cef/blob/master/docs/architecture.md)：C API 與 C++ wrapper 的關係。
- [CEF 官方使用說明](https://github.com/chromiumembedded/cef/blob/master/docs/general_usage.md)：多行程、message loop 與部署概念；涉及舊 runtime 的段落須以本版標頭為準。
- [CEF Automated Builds](https://cef-builds.spotifycdn.com/index.html)：預編譯發行包入口；這次未由網頁確認精確發行列項及發行端 checksum。
