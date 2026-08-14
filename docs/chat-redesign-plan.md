# チャット機能 再設計書
## 「ままより の思想」× 「Track A の業務データ構造」

作成日：2026-08-14

---

## 第1章 現状分析

### 1.1 ままより の実装パターン

ままよりのチャット層は以下のパターンで動作します：

```
【質問】「田中さんの集金、今月まだ何件ある?」

  ↓ 質問解析層（Claude）

【構造化Intent】
{
  "categories": ["shukin"],
  "person": "田中さん",
  "dateFrom": "2026-08-01",
  "dateTo": "2026-08-31",
  "onlyPending": true,
  "granularity": "summary",
  "sortMode": "all"
}

  ↓ 検索層（filterData）

【検索結果】
{
  "shukin": [
    { person: "田中さん", purpose: "○○", amount: 15000, dueDate: "2026-08-15", status: "pending" },
    { person: "田中さん", purpose: "△△", amount: 8000, dueDate: "2026-08-22", status: "pending" }
  ]
}

  ↓ 回答生成層（Claude）

【自然言語回答】
「田中さんの今月の未集金は2件です。8月15日までの○○が15000円、8月22日までの△△が8000円です。」
```

#### ままより の 3 つの特徴

1. **固定キーワード検出をしない**
   - if文で「田中さん」「集金」を個別判定しない
   - 代わりに質問を**構造化JSON**に変換

2. **検索条件が再利用可能**
   - 同じ検索条件構造で、複数の質問に対応可能
   - 将来AIを差し替えても、検索条件のインターフェースは変わらない

3. **チャット専用データを持たない**
   - 既存データから検索するだけ
   - チャット履歴も永続化しない（モジュール変数保持）

---

### 1.2 Track A の現在のデータ構造

#### 業務フロー図

```
【顧客】
 ↓
【案件】← projectId 中心に全データが紐付く
 ├─【見積書】(quotes)
 ├─【追加工事】(changeOrders) ← 未請求 / 請求済み
 ├─【請求書】(invoices)
 ├─【入金】(payments) ← 複数回・分割対応
 ├─【領収書】(paymentReceipts)
 ├─【経費・レシート】(receipts)
 ├─【現場写真】(photos)
 ├─【予定】(scheduleEvents)
 └─【話す入力メモ】(captures) + タスク欄
```

#### 現在のチャット実装

✗ **問題がある実装**：
```javascript
function interpretChatMessage(text) {
  if (/明日/.test(t) && scheduleAsk.test(t)) 
    return { type: "schedule", ... };  // ← 固定キーワード
  
  if (/未請求/.test(t)) 
    return { type: "unbilled" };  // ← 固定キーワード
  
  // ... if文が大量に続く ...
}
```

**現在対応できる質問**：
- 「今日何ある？」
- 「未請求ある？」
- 「未入金ある？」

**対応できない質問**：
- 「8月13日何買ったっけ？」
- 「田中邸どうなってる？」
- 「佐藤さんの全案件見せて」
- 「追加工事が入ってる案件ある？」

---

## 第2章 統合設計

### 2.1 チャット検索条件の構造化

ままよりの検索条件を、Track A のデータ構造に合わせて拡張します：

```javascript
// 統合後の SearchIntent 構造
{
  // データカテゴリ
  "categories": [
    "quotes"          // 見積書
    "invoices"        // 請求書
    "changeOrders"    // 追加工事
    "payments"        // 入金
    "paymentReceipts" // 領収書
    "receipts"        // 経費・レシート
    "photos"          // 現場写真
    "scheduleEvents"  // 予定
    "captures"        // メモ・タスク
  ],
  
  // 案件の特定（複数の方法に対応）
  "projectId":   "proj_xxxxx" | null,       // IDで直接指定
  "projectName": "田中邸" | null,           // 名前で検索
  "customerId":  "cust_xxxxx" | null,       // 顧客IDから検索
  "customerName": "田中さん" | null,        // 顧客名で検索
  
  // 期間
  "dateFrom":   "YYYY-MM-DD" | null,
  "dateTo":     "YYYY-MM-DD" | null,
  
  // ステータス
  "onlyUnbilled": true|false,  // 未請求の見積のみ
  "onlyUnpaid":   true|false,  // 未入金の請求のみ
  "onlyPending":  true|false,  // 完了していない予定のみ
  
  // 回答方法
  "granularity": "summary" | "detail",  // 簡潔 vs 詳細
  "sortMode":    "all" | "nearest"      // 全部 vs 最新1件
}
```

### 2.2 対応する質問パターン例

#### 【検索・確認系】

| 質問 | → | 構造化Intent |
|-----|---|----------|
| 「今日何ある？」 | → | `{ categories: [scheduleEvents], dateFrom: 今日, dateTo: 今日 }` |
| 「8月13日何買ったっけ？」 | → | `{ categories: [receipts], dateFrom: 8/13, dateTo: 8/13 }` |
| 「田中邸どうなってる？」 | → | `{ projectName: "田中邸", categories: [all], granularity: detail }` |
| 「田中さんの案件全部見せて」 | → | `{ customerName: "田中さん", categories: [all], granularity: detail }` |
| 「まだ請求してないものある？」 | → | `{ onlyUnbilled: true, categories: [quotes] }` |
| 「請求済みで入金されてないものある？」 | → | `{ categories: [invoices], onlyUnpaid: true }` |
| 「今月いくら請求した？」 | → | `{ categories: [invoices], dateFrom: 8/1, dateTo: 8/31, granularity: summary }` |
| 「田中邸の追加工事はいくら？」 | → | `{ projectName: "田中邸", categories: [changeOrders], granularity: detail }` |

#### 【登録・操作系】

| 入力 | 分解 | 確認 |
|-----|-----|------|
| 「8月13日、田中邸8時からクロス、10時佐藤邸で建具、1時山田邸現調」 | 3つのscheduleEvent候補を抽出 | ユーザーが案件を確認・選択 |
| 「買い出しはコメリでボード、カインズでコーキング」 | 2つのreceipts候補を抽出 | ユーザーが店舗名・金額を修正 |
| 「田中邸、追加で4万5千円」 | 1つのchangeOrder候補を抽出 | ユーザーが金額・案件を確認 |

---

## 第3章 実装戦略

### 3.1 段階的実装プラン

#### Stage 1: AIなし・ルールベース版（最初）

**目的**：既存データ構造を壊さず、チャット体験を改善

**実装内容**：
1. `interpretChatMessage()` をリニューアル
   - 固定キーワード → 正規表現＋辞書ベースで質問解析
   - 構造化IntentをJSONで出力

2. `filterData()` を新規実装
   - SearchIntentを受け取り、既存データから検索

3. `buildAnswer()` を新規実装
   - 検索結果 → 自然言語回答に変換

**制限事項**：
- 「8月13日何買ったっけ？」のような複雑な質問は精度が落ちる
- 複合入力の分解は対応しない

**メリット**：
- 外部API不要
- セキュリティ上の懸念なし
- 既存データ構造に影響なし

#### Stage 2: AI版（確認後・将来）

**目的**：ままよりの体験を実現

**実装内容**：
1. Netlify Functions で Claude プロキシを実装
   - APIキーはサーバー側で管理
   - フロントエンド（PWA）からはプロキシを呼び出し

2. `interpretChatMessageAI()` を実装
   - ままより方式で質問を構造化JSON に変換

3. 複合入力の分解に対応
   - 複数の情報が混在した入力 → 複数の候補に分解
   - ユーザーが確認・修正

**前提条件**：
- **実装前にユーザー確認が必須**
- APIキーの管理体制が必要
- 課金（Claude API）が発生

---

### 3.2 データ構造への影響

#### ✅ 変更が必要なもの

**現在のchatsとの矛盾**
- 既存の `chatHistory` はモジュール変数で保持（永続化なし）
- ままより方式でも同じで OK

**質問解析層の完全リニューアル**
- 現在の `interpretChatMessage()` は廃止
- 新しい `interpretChatMessage()` に置き換え

#### ✗ 変更しないもの

- **顧客・案件・見積・請求等の既存データ構造** ← 維持
- **業務ロジック層（createChangeOrder等）** ← 維持
- **既存フォーム（docForm等）** ← 維持
- **localStorageでの永続化** ← 維持

---

### 3.3 不足しているデータ型の検討

ままよりにあるが、Track Aにない：
- mochimono（持ち物）← 建設業に不要
- shukin（集金）← 建設業に不要
- teishutsu（提出物）← 建設業に不要

Track Aにあるが、ままよりにない：
- **人工（labor）** ← 「山田は1人工、佐藤は0.5人工」など
- **買い出し（purchase）** ← 既にcapturesの関連タスク欄に含まれている？
- **納品書（deliveryNote）** ← 発注・納品の追跡

**提案**：
- Stage 1では既存の13種類のデータで対応
- 必要に応じて Stage 2 で追加検討

---

## 第4章 セキュリティ・課金への懸念

### 4.1 ままより の実装方式

```javascript
async function callClaude({ system, content, maxTokens = 1200 }) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ 
      model: "claude-sonnet-4-6", 
      max_tokens: maxTokens, 
      system, 
      messages: [{ role: "user", content }] 
    }),
  });
  ...
}
```

### ⚠️ これを Track A に直接適用できない理由

1. **APIキーが見えない**
   - ままよりはClaudeアーティファクト内蔵プロキシを使用
   - GitHub + Netlify で単独公開する場合は不可

2. **セキュリティリスク**
   - APIキーをフロントエンド（PWA側のJS）に埋め込めない
   - 漏洩 → 不正利用 → 課金 → 情報漏洩

3. **個人情報の外部送信**
   - 顧客名「田中さん」「○○邸」
   - 請求金額「15万円」
   - これらがClaudeサーバーに送信される

4. **課金が発生**
   - Claude API は有料
   - ユーザーに事前説明が必要

### ✅ Track A での対応方法

#### **方式1：ルールベースのみ（Stage 1）**
- AI不要
- セキュリティ上の懸念なし
- **推奨**

#### **方式2：Netlify Functions でプロキシ化（Stage 2・確認後）**

フロントエンド（PWA）:
```javascript
// PWA側からプロキシを呼び出し
const response = await fetch("/.netlify/functions/claude-proxy", {
  method: "POST",
  body: JSON.stringify({ 
    system: "...",
    content: "..."
  })
});
```

バックエンド（Netlify Functions）:
```javascript
// サーバー側でAPIキーを管理
const apiKey = process.env.CLAUDE_API_KEY;  // 環境変数から
const response = await fetch("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: { "Authorization": `Bearer ${apiKey}`, ... },
  body: JSON.stringify({ ... })
});
```

**メリット**：
- APIキーがサーバー側で安全に管理される
- フロントエンドに秘密が露出しない
- 個人情報をサーバー側でマスキング可能

**デメリット**：
- Netlify Functions の実装手間
- Claude API の課金が発生
- **実装前にユーザー確認が必須**

---

## 第5章 実装前の確認事項

### 5.1 ユーザー確認が必要な項目

#### ✅ Stage 1（ルールベース・AIなし）

- [ ] 既存の固定キーワード方式を廃止してよいか？
- [ ] 検索条件の構造化に同意するか？
- [ ] 複雑な質問はルールで対応、精度落ちでよいか？

#### ❓ Stage 2（AI導入・要確認）

- [ ] Claude API を使ってよいか？
- [ ] API課金を許容するか？（概算金額を提示）
- [ ] Netlify Functions を導入してよいか？
- [ ] 個人情報がサーバーを経由することを許容するか？
- [ ] APIキー管理の体制を構築できるか？

### 5.2 実装の流れ

1. **本設計書の確認** ← **ここ**
2. ユーザーが「Stage 1 から開始してよいか」を確認
3. 実装開始
4. Stage 1 完成後、「Stage 2 を進めるか」を再確認
5. Stage 2 の実装（必要に応じて）

---

## 第6章 具体的な実装例（Stage 1）

### 6.1 新しい質問解析層（ルールベース版）

```javascript
// 【新実装】
function interpretChatMessage_v2(text) {
  const t = (text || "").trim();
  if (!t) return { type: "empty" };

  // 日付の相対表現を解決
  const dateSpec = resolveDateQuery(t);  // 「今日」→ "2026-08-14"
  
  // カテゴリを推定
  const categories = inferCategories(t);  // 「買った」→ [receipts]
  
  // 案件/顧客を検索
  const { projectName, customerName } = inferEntity(t, data);
  
  // ステータスフィルタ
  const onlyUnbilled = /未請求|未.*請求/.test(t);
  const onlyUnpaid = /未入金|未.*入金|入金.*ない/.test(t);
  
  // 回答粒度
  const granularity = /詳しく|教えて|見せ/.test(t) ? "detail" : "summary";
  
  return {
    type: "search",
    intent: {
      categories,
      projectName,
      customerName,
      dateFrom: dateSpec.from,
      dateTo: dateSpec.to,
      onlyUnbilled,
      onlyUnpaid,
      granularity,
      sortMode: /次|最新|直近/.test(t) ? "nearest" : "all"
    }
  };
}
```

### 6.2 新しい検索層

```javascript
// 【新実装】
function searchByIntent(data, intent) {
  const result = {};
  
  // 案件の特定
  let projects = data.projects;
  if (intent.projectId) {
    projects = projects.filter(p => p.id === intent.projectId);
  } else if (intent.projectName) {
    projects = projects.filter(p => 
      p.name.includes(intent.projectName)
    );
  } else if (intent.customerId) {
    projects = projects.filter(p => 
      p.customerId === intent.customerId
    );
  } else if (intent.customerName) {
    const customer = findCustomer(intent.customerName);
    if (customer) {
      projects = projects.filter(p => 
        p.customerId === customer.id
      );
    }
  }
  
  // 各カテゴリで検索
  if (intent.categories.includes("quotes")) {
    result.quotes = data.quotes.filter(q => {
      if (!projects.map(p => p.id).includes(q.projectId)) return false;
      if (!dateInRange(q.issueDate, intent.dateFrom, intent.dateTo)) return false;
      return true;
    });
  }
  
  // ... invoices, changeOrders, ... も同様
  
  return result;
}
```

### 6.3 新しい回答生成層

```javascript
// 【新実装】
function buildAnswer(intent, searchResult) {
  // 結果がない場合
  if (Object.values(searchResult).every(arr => arr.length === 0)) {
    return "登録されていません。";
  }
  
  // 各カテゴリの情報をまとめる
  const lines = [];
  
  if (searchResult.quotes?.length) {
    const total = searchResult.quotes.reduce((sum, q) => 
      sum + calcTotals(q.items).total, 0
    );
    lines.push(`見積: ${searchResult.quotes.length}件、合計${yen(total)}`);
  }
  
  // granularityに応じて詳細度を変更
  if (intent.granularity === "detail") {
    // 詳細情報を追加
  }
  
  return lines.join("。");
}
```

---

## 第7章 残された質問・検討事項

### 質問1：人工・買い出し・納品書への対応

**現状**：
- 人工 ← `captures` のタスク欄でいいのか？
- 買い出し ← `captures` の関連タスク欄で対応可能？
- 納品書 ← 実装されていない

**検討**：
- Stage 1 では、既存13種類のデータで対応可能か確認
- 必要に応じて、専用データ型の追加を Stage 2 で検討

### 質問2：複合入力への対応

**現状**：
```
「8月13日、田中邸8時からクロス、10時佐藤邸で建具」
→ 3つのscheduleEvent候補を抽出して、ユーザーが確認
```

**検討**：
- Stage 1 ではルールベースでの抽出
- Stage 2 でAIによる複合分解

### 質問3：案件紐付けの確認UI

複合入力時に、ユーザーが「どの案件か」を確認する必要がある。

**案**：
- 候補を表示 → ユーザーが「このscheduleEventは田中邸」と選択
- 既存の `renderProjectPicker()` を再利用可能か検討

### 質問4：API課金の見積

Claude API の概算コスト：
- 質問1件 ≈ 0.1円～1円程度（実装方式による）
- ユーザーが1日10件質問 ≈ 月300円程度

**確認必要**：この費用をユーザーが負担するか、ビジネスモデルを検討

---

## 添付資料

### A. ままより のチャットコード抜粋

see: queryParseSystemPrompt(), answerSystemPrompt(), filterData()

### B. Track A の現在のチャット実装

see: renderChat(), interpretChatMessage(), executeChatQuery()

### C. 用語定義

- **Intent**：質問を構造化したJSON（何を検索したいのか）
- **SearchIntent**：データ検索用のIntent
- **Granularity**：回答の詳細度（summary/detail）
- **projectId**：案件を一意に特定するID

---

## 次のステップ

**このドキュメントについてユーザーから確認を取った後に**：

1. Stage 1 の詳細設計（どの正規表現で質問を解析するか等）
2. Stage 1 の実装開始
3. Stage 1 の動作確認
4. （必要に応じて）Stage 2 の詳細設計・実装

