<p align="center">
  <img src="assets/logo.svg" width="128" height="128" alt="oh-my-agy logo">
</p>

<h1 align="center">oh-my-agy</h1>

<p align="center">
  <strong>看得見現況，留得住經驗。</strong><br>
  Antigravity CLI（<code>agy</code>）的可換主題 statusline 與本機知識庫。
</p>

<p align="center">
  <a href="https://github.com/ChangChunCheng/oh-my-agy/releases"><img src="https://img.shields.io/badge/release-v1.0.0--rc.2-blue" alt="版本"></a>
  <a href="https://github.com/ChangChunCheng/oh-my-agy/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="授權"></a>
</p>

---

<p align="center"><a href="README.md">English</a> | 繁體中文</p>

這個儲存庫提供兩個 [Antigravity CLI](https://antigravity.google) 外掛：**oh-my-status** 與 **oh-my-knowledge**。它們是 [oh-my-claude](https://github.com/sw-willie-wu/oh-my-claude) 的 Claude Code 外掛移植版。

## 外掛

### [oh-my-status](plugins/oh-my-status/README.md)

`agy` 的可換主題 statusline。

- 9 種主題（`catppuccin`、`dracula`、`nord`、`gruvbox`、`tokyonight`、`onedark`、`solarized`、`rosepine`、`mygo`）與 7 種版型（`default`、`minimal`、`powerline`、`pure`、`fancy`、`fancy2`、`mygo`），隨時切換。
- 顯示模型、帳號、目錄、git 分支與變更、context 用量條，以及 5 小時 / 7 天的額度用量條。
- git 資訊有快取，`.git` 的 refs 或 index 一變動就立即失效；不在 git 儲存庫內的目錄不會執行 `git`。

### [oh-my-knowledge](plugins/oh-my-knowledge/README.md)

本機、用 git 版控的知識庫。決策與原因、踩過的雷、慣例、根因這些長期知識集中放在你自己的一個資料夾，專案進度則留在各專案的記憶檔。

- **kb-lookup**：回答疑難類問題前，先搜尋知識庫與該專案的記憶。
- **kb-distill**：把這次 session 學到的東西寫進知識頁。
- **kb-handoff**：session 結束時（或 context 快滿時）更新專案進度，再跑 distill。
- **kb-lint**：健檢斷鏈、過大或過期的頁面與殘留檔。
- **kb-setup**：建立或重新設定知識庫資料夾與其設定。

## 系統需求

- `agy`（Antigravity CLI）
- bash 3.2 以上（建議 bash 5）
- `jq` 1.7 以上
- `git` 2.31 以上
- **oh-my-knowledge** 的 lint 與搜尋需要 `gawk` 與 GNU `find`（`findutils`）：
  - macOS：`brew install gawk findutils jq`（腳本會自動偵測 Homebrew 的 `gawk`／`gfind`，不必手動修改 `PATH`；若想讓終端機預設使用 GNU `find`，可將 `export PATH="$(brew --prefix findutils)/libexec/gnubin:$PATH"` 加入 `~/.zshrc`）。
  - Debian/Ubuntu：`sudo apt install gawk findutils jq`
  - Windows：`winget install jqlang.jq`（Git Bash 已內建 `gawk` 與 GNU `find`）。
- 圖示版型需要 Nerd Font（`pure` 版型不需要）

## 安裝

一行指令同時安裝兩個外掛：

```
agy plugin install https://github.com/ChangChunCheng/oh-my-agy
```

如果**只想安裝其中一個外掛**，直接指定 GitHub 子目錄網址即可（`agy` 目前不支援像 Claude Code 那樣的自訂第三方 `@marketplace` 註冊方式，用子目錄網址就能只裝單一外掛）：

```
# 只裝 oh-my-status
agy plugin install https://github.com/ChangChunCheng/oh-my-agy/tree/main/plugins/oh-my-status

# 只裝 oh-my-knowledge
agy plugin install https://github.com/ChangChunCheng/oh-my-agy/tree/main/plugins/oh-my-knowledge
```

用 `agy plugin list` 確認安裝結果。如果兩個都裝了想停用或移除其中一個，可執行 `agy plugin disable <name>` 或 `agy plugin uninstall <name>`。

> **Windows 注意事項**：`/status-setup`（`configure.sh`）在 Windows 上會自動解析 Git Bash（`Git\bin\bash.exe`）與完整腳本路徑寫入 `settings.json`。但 `agy` 執行外掛的 `hooks.json` 時會使用系統 `PATH` 的 `bash`；若本機同時裝有 WSL，`C:\Windows\System32\bash.exe` 會優先被呼叫並使用 WSL 內的 `/home/<user>`。可在系統 `PATH` 中將 `C:\Program Files\Git\bin` 排在 `System32` 前面，或將已安裝外掛的 `hooks.json` 指令改指向 `C:\PROGRA~1\Git\bin\bash.exe`。

## 首次使用

**oh-my-status**

1. 在 `agy` 中執行 `/status-setup`。它會在詢問後把 `statusLine` 設定加進 `~/.gemini/antigravity-cli/settings.json`，保留其他所有設定，並存一份備份。
2. 用 `/status-themes`（或 `/status-themes layouts`）預覽各種選擇。
3. 用 `/status-theme <主題> [版型]` 切換，例如 `/status-theme tokyonight fancy`。

**oh-my-knowledge**

1. 請 agent 執行 `kb-setup` skill（例如說「設定知識庫」）。它會建立知識庫資料夾（預設 `~/knowledge`），並有自己的 git 歷史；另外會詢問是否把 rules include 加進 `~/.gemini/GEMINI.md`，同樣會先備份。
2. 開新的對話，讓 hooks 讀到知識庫位置。

## 兩個外掛如何配合

oh-my-status 每次繪製時，會把各對話的 context 用量寫進 `~/.gemini/oh-my-agy/state/ctx-<對話 id>`。oh-my-knowledge 的 `Stop` hook 會讀取該檔案，用量達到設定的門檻時，請 agent 執行一次 `kb-handoff`。兩個外掛只共用這些檔案。沒有 oh-my-status 時，自動 handoff 不會運作，手動 handoff 仍可使用。

## 設定檔位置

| 外掛 | 檔案 | 編輯方式 |
| --- | --- | --- |
| oh-my-status | `~/.gemini/oh-my-agy/status.conf` | `/status-theme`，或直接編輯 |
| oh-my-knowledge | `~/.gemini/oh-my-agy/knowledge.conf` | `kb-setup`，或直接編輯 |

兩者都是 shell 風格的 `KEY=value`。每個設定鍵的說明請見各外掛的 README（英文）。

## 執行測試

```
bash tests/run.sh
```

測試使用暫存目錄，不會碰到你真正的 `~/.gemini` 或 `~/knowledge`。

## 致謝

oh-my-agy 移植自 sw-willie-wu 與貢獻者的 [oh-my-claude](https://github.com/sw-willie-wu/oh-my-claude)，同樣採用 MIT 授權。

## 授權

[MIT](LICENSE)
