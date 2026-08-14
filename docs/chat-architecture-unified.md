# チャット機能 統合設計（修正版）
## 「汎用検索エンジン型」- アーキテクチャ

作成日：2026-08-14  
修正：方針変更（小規模段階的 → 汎用拡張可能）

---

## 第1章 要件整理

### 1.1 実現したいチャット体験

**「アプリ内に登録されている情報を横断して、ユーザーが自然な言葉で質問すると、その質問に対して適切な情報を探して答える」**

#### 対応すべき質問例

**検索系**：
- 「今日何ある？」
- 「8月13日何買った？」
- 「田中邸どうなってる？」
- 「田中さんの案件は？」
- 「まだ請求してない案件ある？」
- 「入金されてないものある？」
- 「田中邸の見積はいくら？」
- 「田中邸の追加工事は？」
- 「先月の請求は？」
- 「佐藤さんにいくら請求した？」
- 「この案件の経費は？」
- 「このレシートはどの案件？」
- 「田中邸の写真ある？」
- 「今日の予定と買い出しをまとめて」

**操作系（将来対応）**：
- 「田中邸の請求書を作って」
- 「田中邸、追加工事を請求に含める」

### 1.2 実装フェーズ

#### **Phase 1（現在）**: 汎用検索エンジンの構築
- AIなしでも汎用的に対応できる検索・回答エンジン
- 4層に分離したアーキテクチャ
- ルールベース（正規表現・キーワード）で構造化条件を生成
- **目的**：「質問パターンが増える ≠ コード量が増える」という構造

#### **Phase 2（将来・確認後）**: AI導入
- Claude等のLLMを導入
- 置き換える部分：「自然言語 → 構造化条件」のみ
- それ以外の層（検索・回答）は既存エンジンを使用

#### **Phase 3（さらに将来）**: 登録操作への対応
- チャット経由での「請求書作成」「入金記録」等
- 同じく「自然言語 → 操作Intent」の部分のみ置き換え

---

## 第2章 チャット層の新アーキテクチャ

### 2.1 全体構成

```
┌─────────────────────────────────────────────────────────────┐
│                      ユーザー入力                             │
│                    「田中邸どうなってる？」                     │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│        Layer 1: 質問解析層（ルールベース）                      │
│     「自然言語 → 構造化SearchIntent」                          │
│                                                               │
│  - 正規表現・キーワード・パターンマッチング                      │
│  - 相対日付の解決（「今日」「明日」「来月」等）                  │
│  - 案件・顧客名の抽出                                         │
│  - 検索カテゴリの推定                                         │
│  - ステータスフィルタの推定                                    │
│                                                               │
│  出力: {                                                       │
│    "intent": "project_summary",                              │
│    "searchIntents": [                                        │
│      {                                                        │
│        "type": "project_info",    // 何を検索するか           │
│        "projectId": "proj_xxxxx", // どの案件か              │
│        "categories": [...],       // 見積/請求/人工など       │
│        "filters": {...}           // 期間/ステータス等        │
│      }                                                        │
│    ]                                                          │
│  }                                                            │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│     Layer 2: データ横断検索層（既存データから検索）              │
│                                                               │
│  - 各SearchIntentに対して、既存localStorageから検索            │
│  - projectId/customerId で案件・顧客を特定                    │
│  - 期間・ステータスでフィルタ                                   │
│  - 複数のIntent → 複数の検索結果                               │
│                                                               │
│  出力: {                                                       │
│    "queries": [                                              │
│      {                                                        │
│        "intent": {...},           // 元のSearchIntent        │
│        "result": {                // 検索結果                │
│          "quotes": [...],         // 見積書                  │
│          "invoices": [...],       // 請求書                  │
│          "payments": [...],       // 入金                    │
│          "changeOrders": [...],   // 追加工事                │
│          ...                                                  │
│        }                                                      │
│      }                                                        │
│    ]                                                          │
│  }                                                            │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│      Layer 3: 案件統合層（projectIdで関連情報を統合）            │
│                                                               │
│  - 複数の検索結果を1つの「案件のスナップショット」に統合         │
│  - 顧客 → 案件 → 予定・見積・追加工事・請求・入金・経費等を    │
│    projectId で紐付け                                        │
│                                                               │
│  出力: {                                                       │
│    "projectSummary": {                                       │
│      "projectId": "proj_xxxxx",                              │
│      "customer": {...},           // 顧客情報                │
│      "project": {...},            // 案件情報                │
│      "timeline": [                // 時系列イベント           │
│        { date, type, data },      // 予定                   │
│        { date, type, data },      // 見積作成日               │
│        { date, type, data },      // 請求日                  │
│        ...                                                    │
│      ],                                                       │
│      "financials": {              // 金銭情報                │
│        "quoteAmount": 500000,                                │
│        "changeOrderAmount": 50000,                           │
│        "invoiceAmount": 550000,                              │
│        "paidAmount": 300000,                                 │
│        "pendingAmount": 250000,                              │
│      },                                                       │
│      "currentStage": "invoice_partial_paid",  // 進捗状況     │
│      "documents": [...],          // 見積・請求・領収書等      │
│      "expenses": [...],           // 経費・レシート            │
│      "photos": [...],             // 現場写真                │
│      "nextSchedule": {...},       // 次の予定                │
│    }                                                          │
│  }                                                            │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│         Layer 4: 回答生成層（自然言語で回答）                  │
│                                                               │
│  - 統合された情報から、ユーザーの質問に回答                    │
│  - 情報がない場合は「登録されていません」と明示                │
│  - 関連する画面への遷移情報も生成                              │
│                                                               │
│  出力: {                                                       │
│    "text": "田中邸は...",         // 自然言語回答              │
│    "data": {...},               // 回答に含まれるデータ       │
│    "links": [                   // 関連画面への遷移           │
│      { label: "詳細を見る", type: "projectDetail", id }      │
│    ]                                                          │
│  }                                                            │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                      ユーザーへの回答                          │
│         テキスト + 関連画面への遷移リンク                       │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 各層の詳細

#### **Layer 1: 質問解析層**

**入力**：自由形式の質問テキスト  
**出力**：構造化されたSearchIntent配列

**処理内容**：

```javascript
function interpretQuestion(question) {
  // 1. 質問タイプの判定
  //    - 検索系: "何ある？" "どうなってる？" "いくら？"
  //    - 操作系: "作って" "記録して" "変更して"
  
  // 2. 対象の特定
  //    - 日付: 「今日」「8月13日」「先月」→ ISO日付に変換
  //    - 案件: 「田中邸」→ projectId 検索
  //    - 顧客: 「田中さん」→ customerId 検索
  //    - カテゴリ: 「買った」→ receipts, 「予定」→ scheduleEvents
  
  // 3. フィルタの推定
  //    - 「未請求」→ { onlyUnbilled: true }
  //    - 「入金されてない」→ { onlyUnpaid: true }
  //    - 「最新」「次」→ { sortMode: "nearest" }
  
  // 4. 複数のSearchIntentを生成
  //    例: 「今日の予定と買い出し」
  //    → [
  //      { type: "schedule", date: "2026-08-14" },
  //      { type: "expense", date: "2026-08-14" }
  //    ]
  
  return {
    intent: "search" | "operation",  // または他のタイプ
    searchIntents: [
      {
        type: "...",                // project_info, schedule, etc
        projectId: "..." | null,
        customerId: "..." | null,
        categories: [...],
        filters: {...},
        dateFrom: "...",
        dateTo: "..."
      }
    ]
  };
}
```

**実装上の工夫**：
- 固定キーワードマッチングではなく、正規表現 + パターンベース
- 質問が新しいパターンでも、基本的な検索条件の構造は変わらない
- 例：「○○についてどうなってる？」という新しい聞き方をされても、層2以降は同じロジックで処理可能

---

#### **Layer 2: データ横断検索層**

**入力**：SearchIntent配列  
**出力**：検索結果の配列

**処理内容**：

```javascript
function crossSearchData(searchIntents) {
  return searchIntents.map(intent => {
    // 1. projectId/customerId から対象案件を特定
    let targetProjects = findProjects(intent);
    
    // 2. 各カテゴリで検索
    const result = {};
    intent.categories.forEach(category => {
      result[category] = findByCategory(category, targetProjects, intent.filters);
    });
    
    // 3. 結果がない場合の処理
    // （後層で「登録されていません」と回答）
    
    return { intent, result };
  });
}
```

**重要な特徴**：
- 複数のSearchIntentを並列処理
- 各カテゴリでの検索は独立
- projectId を中心に全データが紐付く構造を活用

---

#### **Layer 3: 案件統合層**

**入力**：検索結果  
**出力**：案件のスナップショット

**処理内容**：

```javascript
function buildProjectSnapshot(searchResults) {
  // 複数の検索結果から、1つの「案件のスナップショット」を構築
  
  // 1. 顧客情報を取得
  // 2. 案件情報を取得
  // 3. timeline に沿って、見積→追加工事→請求→入金→領収書の流れを表示
  // 4. 金銭情報を計算（請求額、請求済み、未入金等）
  // 5. 次のアクション（次の予定、次にやること等）を抽出
  
  return {
    projectId,
    customer,
    project,
    timeline: [...],       // 時系列イベント
    financials: {...},     // 金銭情報
    currentStage,          // 進捗状況
    documents,
    expenses,
    photos,
    nextSchedule,
    nextAction               // ← 「請求書を作成する」等、次にやるべき操作
  };
}
```

**利点**：
- 複数の検索カテゴリをまとめて「案件の現在状況」を把握できる
- 「田中邸どうなってる？」という質問に、見積から入金まで一連の情報で回答
- 後層が簡単になる（多くの情報が統合済み）

---

#### **Layer 4: 回答生成層**

**入力**：案件スナップショット + 元の質問  
**出力**：自然言語回答 + 遷移情報

**処理内容**：

```javascript
function generateAnswer(question, projectSnapshot) {
  // 1. スナップショットから、質問に関連した情報を抽出
  //    例：「追加工事はいくら？」
  //    → projectSnapshot.financials.changeOrderAmount
  
  // 2. 自然言語で回答を生成
  //    - 「登録されていません」と明示（推測しない）
  //    - 数値は見やすく表示（yen()関数等）
  //    - 複数の関連情報も含める
  
  // 3. 関連する画面への遷移リンクを生成
  //    例：「詳細はこちら」→ projectDetail画面へ遷移
  
  return {
    text: "...",           // 自然言語回答
    data: {...},           // 回答に含まれるデータ（UIでハイライト表示等に使用）
    links: [               // 関連画面への遷移
      { label, type, id }
    ]
  };
}
```

---

### 2.3 AI導入時の置き換え箇所

**Phase 2（AI導入時）に置き換える部分は、Layer 1 の「質問解析層」のみ**：

```javascript
// 【現在】ルールベース版
function interpretQuestion_ruleBased(question) {
  // 正規表現・キーワードマッチング
  // → SearchIntent生成
}

// 【Phase 2】AI版
async function interpretQuestion_ai(question) {
  // LLM（Claude等）に「自然言語 → 構造化条件」を任せる
  // ただし出力形式は変わらない
  // → SearchIntent生成（同じ形式）
}

// 【重要】Layer 2-4 は変わらない
// つまり、AIを導入しても、全体のコード大半は修正不要
```

---

## 第3章 データ構造の拡張可能性

### 3.1 現在のデータ型と将来の追加可能性

#### **現在実装済み**（13種類）

```
customers （顧客）
projects （案件） ← projectId 中心
├─ scheduleEvents （予定）
├─ captures （メモ・タスク）
├─ quotes （見積書）
├─ invoices （請求書）
├─ changeOrders （追加工事）
├─ paymentReceipts （領収書）
├─ payments （入金）
├─ receipts （経費・レシート）
└─ photos （現場写真）
```

#### **将来追加可能**（拡張性を考慮した設計）

```
【Phase 2 で追加検討】
├─ laborRecords （人工・工数記録）
│  {
│    projectId: "proj_xxxxx",
│    date: "2026-08-14",
│    worker: "山田太郎",
│    laborDays: 1.5,                // 1.5人工
│    category: "大工" | "電気" | ...,
│    description: "フローリング張替",
│    createdAt: "..."
│  }
│
├─ purchases （買い出し・材料費）
│  {
│    projectId: "proj_xxxxx",
│    date: "2026-08-14",
│    supplier: "コメリ",
│    items: [ { name, qty, unitPrice } ],
│    totalAmount: 15000,
│    createdAt: "..."
│  }
│
├─ deliveryNotes （納品書）
│  {
│    projectId: "proj_xxxxx",
│    date: "2026-08-14",
│    supplier: "○○材木屋",
│    items: [...],
│    totalAmount: 50000,
│    createdAt: "..."
│  }
```

### 3.2 Layer 1-4 での拡張対応

**質問解析層（Layer 1）**：
```javascript
// 現在: categories = [quotes, invoices, scheduleEvents, ...]
// 将来: categories に laborRecords, purchases, deliveryNotes も追加
// → 同じ構造で対応可能
```

**データ横断検索層（Layer 2）**：
```javascript
// 既存と同じ方式で新しいカテゴリを検索可能
// 例：「この案件で何人工？」→ laborRecords を検索
// 例：「買い出しはいくら？」→ purchases を検索
```

**案件統合層（Layer 3）**：
```javascript
// projectSnapshot に新しいフィールドを追加
{
  ...
  labor: {...},           // ← 新規
  purchases: [...],       // ← 新規
  deliveryNotes: [...],   // ← 新規
}
```

**回答生成層（Layer 4）**：
```javascript
// 新しいカテゴリの情報から、回答を生成する処理を追加
// ただし基本構造は変わらない
```

---

## 第4章 ルールベース実装での具体的な工夫

### 4.1 質問パターンの拡張可能性

**現在のアプローチ**（❌ 避けるべき）：
```javascript
if (/今日.*何ある/.test(q)) { /* 処理A */ }
if (/8月.*何買った/.test(q)) { /* 処理B */ }
if (/どうなってる/.test(q)) { /* 処理C */ }
// → 質問が増える度にif文が増える
```

**新しいアプローチ**（✅ 目指すべき）：
```javascript
function interpretQuestion(question) {
  // Step 1: 日付の抽出・正規化
  const dateRange = extractDateRange(question);
  // 「今日」→ { from: "2026-08-14", to: "2026-08-14" }
  // 「先月」→ { from: "2026-07-01", to: "2026-07-31" }
  // 「8月13日」→ { from: "2026-08-13", to: "2026-08-13" }
  
  // Step 2: エンティティの抽出（案件・顧客等）
  const entities = extractEntities(question);
  // { projectNames: ["田中邸"], customerNames: ["田中さん"], ... }
  
  // Step 3: カテゴリの推定（何を知りたいのか）
  const categories = inferCategories(question);
  // 「買った」→ ["receipts"]
  // 「予定」→ ["scheduleEvents"]
  // 「見積」→ ["quotes"]
  
  // Step 4: 目的の推定（何をしたいのか）
  const intent = inferIntent(question);
  // "search" | "operation" | "aggregate"
  
  // Step 5: SearchIntent の組み立て
  return {
    intent,
    searchIntents: [
      {
        type: detectType(question, categories),
        projectNames: entities.projectNames,
        customerNames: entities.customerNames,
        dateFrom: dateRange.from,
        dateTo: dateRange.to,
        categories,
        filters: inferFilters(question)  // 未請求, 未入金等
      }
    ]
  };
}
```

**利点**：
- 新しい質問が来ても、上記の5つの「要素抽出関数」がカバー
- 「○○について△△を知りたい」という形なら、ほぼすべてに対応可能
- 要素抽出関数の精度を上げるだけで、全体の質問対応が改善

### 4.2 よく使うパターンの辞書化

```javascript
// 日付パターン
const DATE_PATTERNS = {
  "今日": () => ({ from: todayStr(), to: todayStr() }),
  "明日": () => ({ from: tomorrowStr(), to: tomorrowStr() }),
  "今週": () => ({ from: weekStartISO(), to: weekEndISO() }),
  "先月": () => ({ from: lastMonthStartISO(), to: lastMonthEndISO() }),
  // ... 等
};

// カテゴリマッピング
const CATEGORY_KEYWORDS = {
  "買った|購入|買い出し": ["receipts"],
  "予定|スケジュール|時間": ["scheduleEvents"],
  "見積|金額": ["quotes"],
  "請求|支払|振込": ["invoices", "payments"],
  "人工|日数": ["laborRecords"],  // ← 将来追加
  // ...
};

// インテント推定
const INTENT_KEYWORDS = {
  "どうなってる|状況|進捗": "project_summary",
  "いくら|金額|合計": "financial_summary",
  "何ある|登録されている": "list_items",
  "作って|記録して|変更": "operation",
  // ...
};
```

---

## 第5章 チャット操作への拡張（将来）

### 5.1 「操作Intent」の設計

**検索と同じ層構造で、操作にも対応**：

```
ユーザー入力
  ↓
「田中邸の追加工事を請求に含める」
  ↓
Layer 1: 自然言語 → OperationIntent
{
  "operation": "add_to_invoice",
  "targetProject": "田中邸",
  "sourceData": "unbilled_change_orders",
  "parameters": { ... }
}
  ↓
Layer 2: 対象データを検索
  (田中邸の未請求追加工事を検索)
  ↓
Layer 3: 操作に必要な情報を統合
  (見積額、既請求額、新規追加額等)
  ↓
Layer 4: 既存の請求書作成機能へ渡す
  go("docForm", { docForm: {...} })
```

**重要**：
- Layer 2-4 は検索と同じ構造を使用
- 将来AIを導入すれば、「自然言語 → OperationIntent」をAIに任せるだけ
- 既存の業務ロジック（createChangeOrder, createDocumentRecord等）は修正不要

---

## 第6章 実装の優先度・スコープ

### 6.1 Phase 1 で実装すべき機能

**必須**：
- [ ] Layer 1: 質問解析層（ルールベース版）
  - 日付抽出・正規化
  - エンティティ抽出（案件・顧客・カテゴリ等）
  - SearchIntent の生成
- [ ] Layer 2: データ横断検索層
  - projectId/customerId による案件検索
  - カテゴリごとのフィルタリング
- [ ] Layer 3: 案件統合層
  - projectSnapshot の構築
  - financials の計算
- [ ] Layer 4: 回答生成層
  - 自然言語での回答
  - 遷移リンクの生成

**チャットUI**：
- [ ] 入力フィールド + 送信ボタン
- [ ] 回答の表示
- 関連画面への遷移リンク

**対応すべき質問（最低限）**：
- 「今日何ある？」
- 「8月13日何買った？」
- 「田中邸どうなってる？」
- 「田中さんの案件は？」
- 「まだ請求してない案件ある？」
- 「入金されてないものある？」
- 「田中邸の見積はいくら？」
- 「先月の請求は？」
- 「この案件の経費は？」
- 「田中邸の写真ある？」

### 6.2 Phase 2 で追加検討

**AI導入**：
- [ ] Netlify Functions でClaudeプロキシを実装（確認後）
- [ ] interpretQuestion_ai() を実装
- [ ] Phase 1のルールベース版と段階的に切り替え

**操作系対応**：
- [ ] OperationIntent の設計
- [ ] 「請求書を作って」等のコマンド対応

**新データ型**：
- [ ] laborRecords （人工）
- [ ] purchases （買い出し）
- [ ] deliveryNotes （納品書）

---

## 第7章 セキュリティ・外部サービスへの方針

### 7.1 Phase 1 で実装しない（課金・セキュリティ懸念）

**実装しないもの**：
- ❌ Claude API （恒常的な課金が発生）
- ❌ OpenAI API （同上）
- ❌ Supabase （個人情報の外部保存）
- ❌ 認証機能 （認証プロバイダの導入）
- ❌ Netlify Functions （Phase 1では不要）
- ❌ 外部連携API （課金またはセキュリティ懸念）

**理由**：
- Phase 1 はルールベースのみで実装可能
- 外部サービスなし = 既存のlocalStorage のみで完結

### 7.2 Phase 2 で検討する場合

**「Netlify Functionsでプロキシ化 + Claude API」を検討する時点で**：

1. **ユーザーに事前確認**
   - API課金（月いくら？）
   - 個人情報のサーバー経由
   - セキュリティ体制

2. **セキュリティ対策**
   - APIキーは環境変数で管理
   - フロントエンドからは見えない
   - 個人情報のマスキング

3. **実装の停止報告**
   - 費用/セキュリティ懸念がある変更は、実装前に必ず報告

---

## 第8章 実装例

### 8.1 Layer 1: 質問解析層の疑似コード

```javascript
// KEYS はTrack Aの既存キー
const KEYS = { ... };

// Step A: 日付パターンの辞書
const DATE_RESOLVERS = {
  "今日": todayStr,
  "明日": tomorrowStr,
  "先月": lastMonthStart,
  // 相対表現も正規表現で対応
  /(\d{1,2})月(\d{1,2})日/: (match) => `${new Date().getFullYear()}-${pad(match[1])}-${pad(match[2])}`
};

// Step B: カテゴリキーワード
const CATEGORY_KEYWORDS = {
  "買|購入|レシート|経費": "receipts",
  "予定|スケジュール|時間": "scheduleEvents",
  "見積|金額|原価": "quotes",
  "請求|支払": ["invoices", "payments"],
  "追加|追加工事": "changeOrders",
  "人工|工数|日数": "laborRecords",  // 将来
  "買い出し|材料|購入": "purchases",  // 将来
  // ...
};

function interpretQuestion(text) {
  const t = text.trim();
  
  // 1. 日付を抽出・正規化
  let dateRange = { from: null, to: null };
  for (const [pattern, resolver] of Object.entries(DATE_RESOLVERS)) {
    if (new RegExp(pattern).test(t)) {
      const result = typeof resolver === 'function' ? resolver() : resolver;
      dateRange = result;
      break;
    }
  }
  
  // 2. エンティティを抽出
  const projectNames = extractProjectNames(t, loadProjects());
  const customerNames = extractCustomerNames(t, loadCustomers());
  
  // 3. カテゴリを推定
  const categories = [];
  for (const [keywords, category] of Object.entries(CATEGORY_KEYWORDS)) {
    if (new RegExp(keywords).test(t)) {
      categories.push(category);
    }
  }
  // カテゴリがなければ「全検索」に設定
  if (categories.length === 0) {
    categories.push("all");  // または複数のデフォルトカテゴリ
  }
  
  // 4. 目的を推定
  let intent = "search";
  if (/作って|記録|変更/.test(t)) intent = "operation";
  
  // 5. フィルタを推定
  const filters = {
    onlyUnbilled: /未請求|請求.*ない/.test(t),
    onlyUnpaid: /未入金|入金.*ない/.test(t),
    sortMode: /次|最新|直近/.test(t) ? "nearest" : "all"
  };
  
  return {
    intent,
    searchIntents: [
      {
        projectNames,
        customerNames,
        dateFrom: dateRange.from,
        dateTo: dateRange.to,
        categories,
        filters
      }
    ]
  };
}
```

### 8.2 Layer 2: データ横断検索層の疑似コード

```javascript
function crossSearch(searchIntent) {
  // 1. 案件を特定
  let projects = loadProjects();
  
  if (searchIntent.projectNames.length > 0) {
    projects = projects.filter(p => 
      searchIntent.projectNames.some(name => p.name.includes(name))
    );
  }
  if (searchIntent.customerNames.length > 0) {
    const customers = loadCustomers().filter(c =>
      searchIntent.customerNames.some(name => c.name.includes(name))
    );
    const customerIds = customers.map(c => c.id);
    projects = projects.filter(p => customerIds.includes(p.customerId));
  }
  
  const projectIds = projects.map(p => p.id);
  
  // 2. 各カテゴリで検索
  const result = {};
  
  searchIntent.categories.forEach(category => {
    switch (category) {
      case "quotes":
        result.quotes = loadList(KEYS.quotes).filter(q =>
          projectIds.includes(q.projectId) &&
          dateInRange(q.issueDate, searchIntent.dateFrom, searchIntent.dateTo)
        );
        break;
      case "invoices":
        result.invoices = loadList(KEYS.invoices).filter(inv => {
          if (!projectIds.includes(inv.projectId)) return false;
          if (!dateInRange(inv.issueDate, searchIntent.dateFrom, searchIntent.dateTo)) return false;
          if (searchIntent.filters.onlyUnpaid) {
            const total = calcTotals(inv.items).total;
            const paidAmount = paymentsForInvoice(inv.id).reduce((s, p) => s + p.amount, 0);
            if (paidAmount >= total) return false;  // 全額入金済みは除外
          }
          return true;
        });
        break;
      // ... receipts, scheduleEvents, ... も同様
      case "all":
        // 全カテゴリを検索
        result.quotes = /* ... */;
        result.invoices = /* ... */;
        result.scheduleEvents = /* ... */;
        // ...
        break;
    }
  });
  
  return {
    projects,
    result
  };
}
```

### 8.3 Layer 3: 案件統合層の疑似コード

```javascript
function buildProjectSnapshot(projects, searchResult) {
  // 複数の案件 → 複数のスナップショット
  return projects.map(project => {
    const customer = findCustomer(project.customerId);
    
    // 金銭情報の計算
    const quotes = searchResult.quotes || [];
    const invoices = searchResult.invoices || [];
    const payments = (searchResult.payments || []);
    
    const quoteAmount = quotes.reduce((s, q) => s + calcTotals(q.items).total, 0);
    const changeOrderAmount = (searchResult.changeOrders || []).reduce((s, c) => s + c.amount, 0);
    const invoiceAmount = invoices.reduce((s, i) => s + calcTotals(i.items).total, 0);
    const paidAmount = payments.reduce((s, p) => s + p.amount, 0);
    const pendingAmount = invoiceAmount - paidAmount;
    
    // タイムラインの構築
    const timeline = [];
    quotes.forEach(q => timeline.push({ date: q.issueDate, type: "quote", data: q }));
    invoices.forEach(i => timeline.push({ date: i.issueDate, type: "invoice", data: i }));
    payments.forEach(p => timeline.push({ date: p.date, type: "payment", data: p }));
    timeline.sort((a, b) => a.date.localeCompare(b.date));
    
    // 進捗状況の判定
    let currentStage = "created";
    if (quotes.length > 0) currentStage = "quoted";
    if (invoices.length > 0) currentStage = "invoiced";
    if (pendingAmount === 0 && invoiceAmount > 0) currentStage = "fully_paid";
    
    return {
      projectId: project.id,
      customer,
      project,
      timeline,
      financials: {
        quoteAmount,
        changeOrderAmount,
        invoiceAmount,
        paidAmount,
        pendingAmount
      },
      currentStage,
      documents: {
        quotes,
        invoices,
        paymentReceipts: searchResult.paymentReceipts || []
      },
      expenses: searchResult.receipts || [],
      photos: searchResult.photos || [],
      schedules: searchResult.scheduleEvents || [],
      nextSchedule: (searchResult.scheduleEvents || []).find(s => s.date >= todayStr())
    };
  });
}
```

### 8.4 Layer 4: 回答生成層の疑似コード

```javascript
function generateAnswer(question, snapshots) {
  // 質問内容に応じた回答生成
  
  if (/どうなってる|状況|進捗/.test(question)) {
    // 「どうなってる？」系 → 案件全体のサマリー
    return snapshots.map(snap => {
      const lines = [];
      lines.push(`案件: ${snap.project.name}`);
      lines.push(`顧客: ${snap.customer?.name || "未設定"}`);
      lines.push(`見積: ${yen(snap.financials.quoteAmount)}`);
      lines.push(`請求: ${yen(snap.financials.invoiceAmount)}`);
      lines.push(`入金: ${yen(snap.financials.paidAmount)}`);
      if (snap.financials.pendingAmount > 0) {
        lines.push(`未入金: ${yen(snap.financials.pendingAmount)}`);
      }
      return lines.join("\n");
    }).join("\n\n");
  }
  
  if (/いくら|金額|合計/.test(question)) {
    // 「いくら？」系 → 金額情報
    const amounts = snapshots.map(snap => {
      if (/請求/.test(question)) return snap.financials.invoiceAmount;
      if (/見積/.test(question)) return snap.financials.quoteAmount;
      if (/入金|支払済/.test(question)) return snap.financials.paidAmount;
      return snap.financials.invoiceAmount;  // デフォルト
    });
    
    if (amounts.length === 0) return "登録されていません。";
    if (amounts.length === 1) return `${yen(amounts[0])}です。`;
    return `合計 ${yen(amounts.reduce((a, b) => a + b))} です。（案件ごと: ${amounts.map(a => yen(a)).join(", ")}）`;
  }
  
  if (/何ある/.test(question)) {
    // 「何ある？」系 → リスト表示
    if (snapshots.length === 0) return "登録されていません。";
    return snapshots.map(snap => {
      const items = [];
      if (snap.schedules.length > 0) items.push(`予定: ${snap.schedules.length}件`);
      if (snap.documents.invoices.length > 0) items.push(`請求書: ${snap.documents.invoices.length}件`);
      if (snap.financials.pendingAmount > 0) items.push(`未入金: ${yen(snap.financials.pendingAmount)}`);
      return `${snap.project.name}: ${items.join(", ")}`;
    }).join("\n");
  }
  
  // その他のパターン...
  
  return "申し訳ありません。その質問にはまだ対応していません。";
}
```

---

## 第9章 実装の流れ

### 9.1 段階的実装スケジュール（案）

**Week 1: Layer 1 + 2 の実装**
- [ ] 質問解析層（ルールベース）
- [ ] データ横断検索層
- [ ] 基本的な質問に対応

**Week 2: Layer 3 + 4 の実装**
- [ ] 案件統合層
- [ ] 回答生成層
- [ ] UIの整備

**Week 3: テスト・改善**
- [ ] 対応質問の追加
- [ ] エラーハンドリング
- [ ] UI改善

**Week 4+: 拡張**
- [ ] 新データ型への対応（人工、買い出し等）
- [ ] 操作Intent の検討
- [ ] AI導入の判断

---

## 第10章 残された確認事項

### 必須確認

1. [ ] 4層の分離アーキテクチャに同意するか？
2. [ ] ルールベース版で「最低限の対応質問」に同意するか？
   - （完全カバーは目指さず、層構造で拡張性を重視）
3. [ ] データ構造の拡張可能性設計に同意するか？
4. [ ] Phase 1 ではAI/外部API を導入しないことに同意するか？

### 将来の判断ポイント

5. [ ] Phase 2 で AI を導入するか？
   - If Yes: Netlify Functions + Claude API の体制構築
   - 実装前に必ずユーザー確認が必須

6. [ ] 人工・買い出し・納品書をいつ追加するか？
   - Phase 2 と同時か、別フェーズか

---

## 付録: 用語定義

- **SearchIntent**: 質問を構造化した検索条件オブジェクト
- **OperationIntent**: 操作指示を構造化したオブジェクト（将来）
- **Layer**: 責務ごとに分離された処理層
- **projectSnapshot**: 1つの案件に関連するすべての情報を統合したオブジェクト
- **cross-search**: 複数のデータ型を横断して検索すること

---

## まとめ

このアーキテクチャにより、以下を実現します：

✅ **AIなしでも汎用的** → ルールベースで大多数の質問に対応  
✅ **拡張可能** → 新しい質問パターンが来ても層構造で吸収  
✅ **AI対応可能** → Phase 2 で Layer 1 のみ置き換え  
✅ **安全** → 外部サービス・課金・セキュリティ懸念なし  
✅ **将来に向けた設計** → 人工・買い出し等の追加に耐える  

**最初から「大きく・拡張可能に」作ることで、将来の作り直しを避けられます。**

