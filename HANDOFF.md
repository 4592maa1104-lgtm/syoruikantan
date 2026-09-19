# HANDOFF.md — 引継ぎ資料（コード側の実態ベース）

最終更新: 2026-09-19。以下はすべて実際のファイル・git履歴・Netlify画面から確認した内容。
CLAUDE.mdやdocs/配下の記述と実装がズレている箇所は「実装が正」として本文中に明記した。

---

## 1. アプリの概要

建築業の一人親方（個人事業主）が、スマートフォンに話しかけるだけで見積書・請求書・
レシート・経費・スケジュールなどの事務作業を完結できるようにするPWA。「フォーム入力」
ではなく「音声入力→AI/ルールベースで整理→人が確認→保存」を基本フローとする。

- 公開URL: https://syoruikantan.netlify.app
- 想定利用者: アプリ開発を依頼した本人（個人事業主）1名。複数テナント設計ではない
- 主対象端末: Android（Web Speech APIの音声認識がChromeで動作するため）。iPhone Safariは音声認識非対応

**CLAUDE.mdとの相違点**: CLAUDE.mdの「現在地」節は `prototype/index.html` を本体として説明しているが、
実際には `prototype/` は空フォルダで、**本体はリポジトリ直下の `index.html`（3362行）**。
また、CLAUDE.mdにはSupabase連携・ログイン機能・AI要約機能への言及が一切ないが、
これらはコード上に実装済み（現在は無効化。5章・6章参照）。CLAUDE.mdは更新が追いついていない。

---

## 2. 技術スタックと主要ライブラリ

`package.json` は存在しない（ビルド工程なし、npmパッケージ管理をしていない）。
外部ライブラリはすべてCDN読み込み（`index.html` 8〜12行目）:

| ライブラリ | バージョン | 用途 |
|---|---|---|
| xlsx (SheetJS) | 0.18.5 | Excelダウンロード（数値のみ、書式非対応） |
| tesseract.js | 5系（マイナー固定なし） | レシート画像の簡易OCR |
| @supabase/supabase-js | 2系（マイナー固定なし） | Supabase接続（現在無効化中） |

サーバー側は Supabase Edge Functions（Deno）が1本のみ存在（`supabase/functions/ai-structure/index.ts`）。
こちらも `package.json` 等のNode依存はなく、Deno標準APIのみで完結。

---

## 3. ディレクトリ構成（`src`は存在しない。リポジトリ直下〜2階層）

```
./index.html                         # アプリ本体。全ロジック・全画面がこの1ファイルに集約
./CLAUDE.md                          # 開発方針（一部CLAUDE.md自体が実装より古い。1章参照）
./docs/requirements.md               # 要件定義。仕様判断の一次情報源
./docs/phase1-implementation-report.md  # チャット4層構造の実装報告（内容は実装と一致）
./docs/chat-architecture-phase1.md   # チャット設計の検討資料（開発途中版、最終実装と差異あり）
./docs/chat-architecture-unified.md  # 同上（統合版）
./docs/chat-redesign-plan.md         # 同上（AI導入案などの検討メモ）
./supabase/schema.sql                # Supabaseテーブル定義・RLSポリシー（現行プロジェクトは消滅疑い、5章）
./supabase/functions/ai-structure/index.ts  # AI要約用Edge Function（Claude API呼び出し、現在未使用）
./AI要約機能_デプロイ手順.md          # 上記Edge Functionのデプロイ手順（有料API利用を含む）
./引継ぎ資料.md                       # 人間向けの別引継ぎメモ（本ファイルと内容重複あり）
./prototype/                         # 空フォルダ（旧 prototype/index.html は削除済み、6142a0bで統一）
./claude_model_list.html             # アプリ本体と無関係の別ファイル（Claudeモデル一覧、由来不明）
./.claude/settings.json, settings.local.json  # Claude Code設定
```

---

## 4. 機能一覧と実装ファイルの対応表

全機能は `index.html` 内に集約。層ごとにコメントで区切られている（データ操作層→業務ロジック層
→Query層→Chat Command Layer→UI/イベント層）。

| 機能 | 主要関数（`index.html`内、行番号） |
|---|---|
| 顧客・案件管理 | `createOrReuseCustomerAndProject`(536), `loadCustomers`/`loadProjects`(527-530) |
| 見積書・請求書・領収書作成 | `createDocumentRecord`(646), `defaultDocForm`(1405), `renderDocForm`(2107), `exportXlsx`(1662) |
| 追加見積書（承認フロー） | `defaultAdditionalQuoteForm`(1432), `nextAdditionalQuoteNumber`(1424), `setQuoteApprovalStatus`(596) |
| 追加工事 | `createChangeOrder`(637), `unbilledChangeOrders`(572) |
| 入金管理（分割対応） | `recordPayment`(721), `getInvoicePaymentInfo`(734) |
| レシート撮影・OCR・経費登録 | `createExpenseRecord`(700), `runReceiptOCR`(1635), `renderReceiptCapture`(1956) |
| レシート複数枚一括登録 | `advanceReceiptBatchOrFinish`(1987) |
| スケジュール管理 | `createScheduleEvent`(768), `todaysScheduleEvents`(780) |
| 話す・入力（音声/簡易AI整理） | `toggleMic`(1582), `structureText`(1487)＝無料ルールベース, `callAiStructure`(1528)＝AI要約（現在無効） |
| チャット業務アシスタント | `interpretQuestion`(987)→`crossSearchData`(1036)→`buildProjectSnapshot`(1085)→`generateAnswer`(1142) |
| Supabase二重保存（現在無効） | `enqueueSyncUpsert`(376), `processSyncQueue`(435) |
| ログイン（現在無効） | `renderLogin`(1798), `signIn`(255), `boot`(3345) |

UI描画は `render()`(1741) が `state.view` に応じて `render*` 関数群（1798〜2645行台）を呼び出す
単純な自前ルーティング。フレームワーク不使用。

---

## 5. データの持ち方

### localStorage（`KEYS`オブジェクト、189〜195行目。すべて末尾`_v1`）

`captures_v1`（話す入力メモ）, `receipts_v1`（経費レシート）, `quotes_v1`, `invoices_v1`,
`payment_receipts_v1`（領収書）, `company_profile_v1`, `customers_v1`, `projects_v1`,
`change_orders_v1`（追加工事）, `item_presets_v1`（よく使う工事項目）, `payments_v1`（入金記録）,
`photos_v1`（現場写真）, `schedule_events_v1`, `sync_queue_v1`（Supabase未送信キュー）

読み取りは常に100% localStorage。Supabaseは書き込みの保険用途のみ（コード内コメント247行目付近）。

### Supabaseテーブル定義（`supabase/schema.sql`。**現行プロジェクトは疑わしい、5章参照**）

customers, projects, quotes, invoices, payment_receipts, change_orders, payments,
expense_receipts, photos, schedule_events, captures, item_presets, company_profile（計13テーブル）。
localStorageの各キーとほぼ1:1対応。RLSは「認証済みユーザーのみ全操作可」の単一テナント方針
（`auth.role() = 'authenticated'`、行ごとの所有者管理なし）。Storageバケット`app-images`も同方針。

### 同期の仕組み

`enqueueSyncUpsert`/`enqueueSyncDelete`(376,387) が `sync_queue_v1` にタスクを積み、
`processSyncQueue`(435) が起動時・45秒毎（`setInterval`, 3348行目）・`online`イベント時に送信を試みる。
`syncWatchdogTimer`(432) が40秒で強制的にロック解除する安全装置あり。
**`isSupabaseConfigured()`(212) が現在常にfalseのため、この同期処理は実質的に完全停止中。**

---

## 6. 認証まわりの流れ（現在は機能停止中）

`SUPABASE_URL`/`SUPABASE_ANON_KEY`（204-209行目）が**意図的に空文字**にされている
（コメントに理由あり: 「ログイン用アカウントのパスワード不明でロックアウトされたため」）。
元の値はコメントアウトで同じ場所に残っている。

有効時の想定フロー: `boot()`(3345) → `isSupabaseConfigured()`がtrueなら `getAuthSession`(248) で
セッション確認 → セッション無ければ `renderLogin`(1798) 画面へ → `signIn(email, password)`(255) が
Supabase Authの `signInWithPassword` を呼ぶ → 成功で `go("home")` + `processSyncQueue()`。

**現状**: `isSupabaseConfigured()` が常にfalseなので `boot()` は即座に `render()` してホーム画面へ行き、
ログイン画面自体に到達しない。認証・同期・AI要約（6.5参照）はすべて事実上オフ。

Anon Key（209行目にコメントアウトで残存）は公開前提のpublishable keyであり秘密鍵ではない
（コード内コメントにも明記）。ただし本ファイルには値そのものは転記しない。

---

## 7. 未完成の部分・既知のバグ・触ると壊れやすい箇所

- **Supabaseプロジェクトが応答しない**: 元の接続先ホスト名がDNS解決不能（`net::ERR_NAME_NOT_RESOLVED`、
  2026-09-19に確認）。無料枠の長期未使用による自動停止/削除が濃厚だが、Supabaseダッシュボード側で
  未確認。**再有効化するには新規プロジェクト作成が必要な可能性が高い**
- **AI要約機能（`callAiStructure`, 1528行目）は未デプロイの疑い**: `supabase/functions/ai-structure/index.ts`
  はリポジトリに存在するが、Anthropic APIキーをSupabase Secretsに登録する手順
  （`AI要約機能_デプロイ手順.md`）が実際に完了したかは未確認。加えて現在Supabase自体が
  無効なので、有効/未完了に関わらず呼び出されない
  - ユーザーからは「APIキーの課金は使わない方向で」と明確な意思表示あり（2026-09時点）
- **「🎙 話す・入力」機能に既知の不具合あり**（ユーザー報告、詳細未特定・未調査。過去のタスクで
  意図的にスコープ外とされた経緯あり）
- **`index_phase1_dualsave_2.html`** がリポジトリ直下に未追跡（untracked）のまま残存。
  古いバックアップ的ファイルで、アプリの一部ではない。コミット対象から明示的に除外済み
- **Netlify無料枠のデプロイ用クレジット超過**が過去2回発生し、GitHubにpushしても本番に
  反映されない状態が発生した（Deploysタブに`Skipped due to account credit usage exceeded`）。
  月次リセット後に手動で`Trigger deploy`が必要になる場合がある
- 自動テストは存在しない（テストフレームワーク・CIとも未導入）。変更後は手動確認が必須
- 領収書の税務上の正式な扱い（電子帳簿保存法・収入印紙の実物貼付）は未対応・未確認
  （`docs/requirements.md` 21章）

---

## 8. ビルドとデプロイの手順

ビルド工程なし（静的HTML1ファイルをそのまま配信）。

- **ソース管理**: GitHub `github.com/4592maa1104-lgtm/syoruikantan`（ブランチ: `main`のみ）
- **デプロイ方式**: Netlifyの「Deploys from github.com/4592maa1104-lgtm/syoruikantan」でGitHub連携済み。
  `main`へのpushで自動デプロイ（Netlify側「Auto publishing is on」）。ビルドコマンドなし、
  公開ディレクトリはリポジトリ直下（`index.html`をそのまま配信）
- **手動再デプロイ**: Netlifyダッシュボード → プロジェクト`syoruikantan` → `Deploys`タブ →
  右上「Trigger deploy」→「Deploy project」
- **反映確認方法**: `https://syoruikantan.netlify.app` を直接fetchし、`SUPABASE_URL =` の行の値を
  確認するとデプロイ済み内容を外部から検証できる（本セッションで実施した実例あり）
- **ローカル動作確認**: ビルド不要。`index.html`をブラウザで直接開くか、ローカルの簡易HTTPサーバーで
  配信すればよい（ただしマイク等ブラウザAPIはHTTPS必須のため、file://では一部機能が動かない）

git remote: `origin` = `https://github.com/4592maa1104-lgtm/syoruikantan.git`（fetch/push共通）

---

## 9. 直近のgit log（全履歴。本リポジトリは5コミットのみで、20件に満たない）

```
0dac933  2026-09-11  ログイン機能を緊急停止(パスワード不明のためロックアウト復旧)
e7f7203  2026-08-15  Phase 1: Supabase二重保存・オフライン同期キューを実装
ae679e4  2026-08-14  Supabase接続基盤とログイン機能を追加（Phase 0）
fd1866b  2026-08-14  チャットのデッドコード削除・入金額バグ修正・追加見積書機能を追加
6142a0b  2026-08-14  ローカル(Aiの作業場)の内容でリポジトリを統一
```

`6142a0b`が実質的な初期コミット（それ以前のGit履歴は別セッションで新規統一されたため存在しない）。
