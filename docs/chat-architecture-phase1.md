# チャット機能 Phase 1 実装設計
## 「情報横断検索エンジン」- 方針確定版

作成日：2026-08-14  
確定日：2026-08-14（ユーザー確認後）

---

# 【重要な方針確認】Phase 1 3つの条件

## ✅ 条件【1】チャットの目的と固定if文の禁止

### チャットの存在目的
```
「このアプリに登録されている情報を、
  ユーザーが自然な言葉で横断的に確認できる入口」
```

### ❌ 絶対禁止：固定if文の大量増加
```javascript
// こういう書き方は禁止
if (question.includes("田中邸") && question.includes("どうなってる")) { ... }
if (question.includes("田中邸") && question.includes("請求")) { ... }
if (question.includes("田中邸") && question.includes("入金")) { ... }
```

### ✅ 要求：同じ意味の異なる表現を同じロジックで処理
```
表現が違っても、同じ意味の質問
  ↓
同じ検索ロジックで処理
  ↓
質問数が増える ≠ コード量が増える
```

### 実装方法：「要素抽出」型

```javascript
function interpretQuestion(question) {
  // Layer 1: 質問を分解して「要素」を抽出
  
  // 要素1: 日付を抽出して正規化
  const dateRange = extractDateRange(question);
  
  // 要素2: 対象エンティティ（案件・顧客）を抽出
  const targetProject = extractProjectName(question);
  const targetCustomer = extractCustomerName(question);
  
  // 要素3: 検索カテゴリを推定
  const categories = inferCategories(question);
  
  // 要素4: フィルタ条件を推定
  const filters = inferFilters(question);
  
  // 要素5: 応答形式を判定
  const responseFormat = inferResponseFormat(question);
  
  // Layer 1 出力：構造化された SearchIntent
  return {
    targetProject,
    targetCustomer,
    dateRange,
    categories,
    filters,
    responseFormat
  };
}
```

**メリット**：
- 「○○について△△を知りたい」という構文なら、ほぼ全ての質問に対応可能
- 新しい質問が来ても、5つの抽出関数の精度改善のみで対応
- if-else文の追加は最小限（むしろ減る）

---

## ✅ 条件【2】回答できない場合の扱い

### ❌ 禁止：ツンデレ対応
```
「対応していません」
「この質問には答えられません」
→ 終わり
```

### ✅ 要求：何が分かっていて何が分からないか明確に

```javascript
function generateAnswer(question, projectSnapshot) {
  // Layer 4: 回答生成
  
  // 【重要】情報がない場合も「回答」として返す
  // （「分かりません」ではなく「登録されていません」）
  
  if (searchResult.length === 0) {
    // 「田中邸について検索したけど情報がない」→ 明示
    return {
      text: `田中邸について登録されている情報を検索しましたが、
             ${categories} には登録されていません。`,
      isPartial: true,
      searchedIn: categories  // 「どこを探したか」を示す
    };
  }
  
  // 【重要】部分的な情報の場合も、存在する部分を返す
  if (searchResult.partial) {
    return {
      text: `田中邸は見積50万・請求50万・入金30万で登録されていますが、
             追加工事の記録がないため、新規工事分はまだ登録されていないかもしれません。`,
      partialReason: "category_missing",
      availableData: [...],
      missingData: [...]
    };
  }
  
  return {
    text: "...",
    data: {...}
  };
}
```

### 回答テンプレート集

```
【パターン1】情報あり
「田中邸は見積50万・請求50万・入金30万です。」

【パターン2】情報がない
「田中邸について、{カテゴリ} の登録がありません。」

【パターン3】部分的な情報
「田中邸は見積50万・請求50万ですが、
 追加工事の記録が見つかりません。」

【パターン4】参考情報を追加
「先月の請求は全体で120万です。
 内訳：田中邸50万、佐藤邸40万、田辺邸30万」

【パターン5】次のアクションを提案
「田中邸は請求済みですが、入金がまだ20万残っています。
 → [詳細を見る] [入金を記録する]」
```

### ❌ 禁止：フォールバック機能

```javascript
// こういう「フォールバック」は禁止
if (!understood(question)) {
  // 質問と判定できなかった → メモとして保存
  saveAsCapture(question);
  return { type: "capture", text: "メモに保存しました" };
}
```

**理由**：
- ユーザーが質問している意図を無視している
- 検索エンジンのはずなのに、データ入力モードに切り替わってしまう
- ルールベースには限界があるが、その限界をユーザーに知らせるべき

---

## ✅ 条件【3】案件データの将来拡張（共通データモデル）

### 全体像：一貫したデータ構造

```
顧客 (customerId)
  ↓
案件 (projectId) ← 全データの中心
  ↓
  ├─ 予定 (scheduleEvents)
  │  { projectId, date, description, ... }
  │
  ├─ 人工 (laborRecords) ← 将来追加
  │  { projectId, date, workerId, laborDays, ... }
  │
  ├─ 買い出し (purchases) ← 将来追加
  │  { projectId, date, supplier, totalAmount, ... }
  │
  ├─ 見積 (quotes)
  │  { projectId, date, amount, items: [...], ... }
  │
  ├─ 追加工事 (changeOrders)
  │  { projectId, quoteId, amount, status, ... }
  │
  ├─ 請求 (invoices)
  │  { projectId, date, amount, items: [...], ... }
  │
  ├─ 入金 (payments)
  │  { projectId, invoiceId, amount, date, ... }
  │
  ├─ 領収書 (paymentReceipts)
  │  { projectId, paymentId, ... }
  │
  ├─ 経費・レシート (receipts)
  │  { projectId, date, amount, category, ... }
  │
  ├─ 納品書 (deliveryNotes) ← 将来追加
  │  { projectId, date, supplier, items: [...], ... }
  │
  └─ 現場写真 (photos)
     { projectId, date, url, description, ... }
```

### 共通プロパティ：すべてのデータ型が持つべきフィールド

```javascript
{
  // ■ ID関連（必須）
  id: "xxxx",               // ユニークID
  projectId: "proj_xxxxx",  // ← 【重要】すべてのデータが持つ
  
  // ■ タイムスタンプ
  date: "2026-08-14",       // そのデータが発生した日付
  createdAt: "2026-08-14T...",  // アプリに記録した日時
  
  // ■ 金額関連（額の伴うデータ）
  amount: 50000,            // 金額
  currency: "JPY",
  
  // ■ メタデータ
  type: "labor" | "purchase" | ...,
  status: "draft" | "confirmed" | "archived",
  
  // ■ 検索・グループ化用
  category: "大工" | "電気" | ...,  // 金額の有無やカテゴリが異なる
  
  // ■ テキスト
  description: "...",
  notes: "..."
}
```

### Layer 2: データ横断検索層での拡張対応

```javascript
function crossSearchData(searchIntent) {
  // 【関数の基本構造は変わらない】
  // 新しいカテゴリを追加するだけで対応可能
  
  const allCategories = [
    "scheduleEvents",
    "laborRecords",       // ← 将来追加しても、ここに1行追加するだけ
    "purchases",          // ← ここに1行追加するだけ
    "quotes",
    "invoices",
    "payments",
    // ... 既存カテゴリ ...
  ];
  
  const result = {};
  allCategories.forEach(category => {
    if (searchIntent.categories.includes(category)) {
      result[category] = localStorage[KEYS[category]]
        .filter(item => item.projectId === targetProjectId)
        .filter(item => matchesFilters(item, searchIntent.filters));
    }
  });
  
  return result;
}
```

### Layer 3: 案件統合層での拡張対応

```javascript
function buildProjectSnapshot(projectId, searchResults) {
  // 現在の financials を計算する関数
  const current = calcFinancials(searchResults);
  
  // 【拡張】laborRecords が追加されたら
  if (searchResults.laborRecords?.length > 0) {
    current.totalLaborDays = sum(sr.laborRecords, d => d.laborDays);
    current.laborCost = current.totalLaborDays * 10000;  // 1人工 = 10000円
  }
  
  // 【拡張】purchases が追加されたら
  if (searchResults.purchases?.length > 0) {
    current.totalPurchaseAmount = sum(sr.purchases, p => p.totalAmount);
  }
  
  // 【結果】既存のロジックを修正せず、新しいフィールドを追加するだけ
  return {
    projectId,
    customer: {...},
    project: {...},
    timeline: buildTimeline(searchResults),  // ← 時系列に全カテゴリを混在
    financials: {
      ...current,
      // 新しいカテゴリの金銭情報も追加
      laborCost: current.laborCost || 0,
      purchaseAmount: current.totalPurchaseAmount || 0,
      totalCost: (current.laborCost || 0) + (current.totalPurchaseAmount || 0),
    },
    documents: {...},
    expenses: {...},
    // 【新規】新しいカテゴリのデータも追加
    labor: searchResults.laborRecords || [],
    purchases: searchResults.purchases || [],
    deliveryNotes: searchResults.deliveryNotes || [],
  };
}
```

### Layer 4: 回答生成層での拡張対応

```javascript
function generateAnswer(question, projectSnapshot) {
  // 「この案件で何人工？」という質問が来たら
  if (question.includes("人工")) {
    const laborDays = projectSnapshot.labor
      ?.reduce((sum, item) => sum + item.laborDays, 0) || 0;
    
    if (laborDays === 0) {
      return {
        text: `田中邸の人工記録が登録されていません。`,
        isPartial: true
      };
    }
    
    return {
      text: `田中邸は合計 ${laborDays} 人工です。`,
      data: { laborDays }
    };
  }
  
  // 「買い出しはいくら？」という質問が来たら
  if (question.includes("買い出し")) {
    const purchases = projectSnapshot.purchases || [];
    if (purchases.length === 0) {
      return {
        text: `田中邸の買い出し記録が登録されていません。`,
        isPartial: true
      };
    }
    
    const total = sum(purchases, p => p.totalAmount);
    return {
      text: `田中邸の買い出しは合計 ${yen(total)} です。`,
      data: { purchases }
    };
  }
}
```

**重要**：
- Layer 1-4 の基本構造は変わらない
- 新しいカテゴリが追加されても、1行程度の修正で対応可能
- 既存機能を壊す必要がない

---

# 第1章 Layer 1: 質問解析層（ルールベース）

## 1.1 Layer 1 の責務

```
入力: 自由形式の質問テキスト
  ↓
5つの「要素抽出関数」で分解
  ↓
出力: 構造化されたSearchIntent
```

## 1.2 実装する5つの要素抽出関数

### 【関数1】`extractDateRange(question)`

```javascript
function extractDateRange(question) {
  // 相対日付を ISO 日付に変換
  
  // 「今日」→ 2026-08-14
  if (/今日|今日の/.test(question)) {
    return { from: todayISO(), to: todayISO() };
  }
  
  // 「明日」→ 2026-08-15
  if (/明日/.test(question)) {
    return { from: tomorrowISO(), to: tomorrowISO() };
  }
  
  // 「今週」→ 2026-08-11 ~ 2026-08-17
  if (/今週/.test(question)) {
    return { from: weekStartISO(), to: weekEndISO() };
  }
  
  // 「先月」→ 2026-07-01 ~ 2026-07-31
  if (/先月|上月/.test(question)) {
    return { from: lastMonthStartISO(), to: lastMonthEndISO() };
  }
  
  // 「8月13日」「8/13」→ 2026-08-13
  const dateMatch = question.match(/(\d{1,4})年?(\d{1,2})月(\d{1,2})日?/);
  if (dateMatch) {
    return {
      from: dateToISO(dateMatch[1], dateMatch[2], dateMatch[3]),
      to: dateToISO(dateMatch[1], dateMatch[2], dateMatch[3])
    };
  }
  
  // 日付なし
  return { from: null, to: null };
}
```

### 【関数2】`extractProjectName(question)`

```javascript
function extractProjectName(question) {
  // 質問に含まれる「案件名」を抽出
  
  // 「田中邸」「田中さんの案件」等から「田中邸」を抽出
  const match = question.match(/([a-z一-龥ぁ-ゔァ-ヴー々〆〤ㄱ-ㅎㅏ-ㅣ가-힣]+)(?:邸|さん|様|のお客|の案件|の工事|について|の|は)?/);
  
  if (match) {
    return {
      name: match[1],
      // 後でlocalStorageで projectId に変換
    };
  }
  
  return null;
}
```

### 【関数3】`extractCustomerName(question)`

```javascript
function extractCustomerName(question) {
  // 顧客名を抽出（案件名とは別に、顧客のみを指す場合）
  
  // 「田中さん」「田辺様」→ 「田中」「田辺」
  const match = question.match(/([a-z一-龥ぁ-ゔァ-ヴー々〆〤]+)(?:さん|様|氏|が|は|へ|に)?/);
  
  if (match) {
    return {
      name: match[1],
      // 後でlocalStorageで customerIds に変換
    };
  }
  
  return null;
}
```

### 【関数4】`inferCategories(question)`

```javascript
function inferCategories(question) {
  // 質問から「何を検索したいのか」を推定
  
  const categories = [];
  
  // キーワード → カテゴリ マッピング
  const keywordMap = {
    "予定|スケジュール|時間|ある|いつ": ["scheduleEvents"],
    "買った|買い出し|購入|支出|何買った": ["receipts", "purchases"],  // 将来 purchases も
    "見積|金額|いくら": ["quotes"],
    "請求|支払|振込": ["invoices", "payments"],
    "追加工事|工事|変更": ["changeOrders"],
    "入金|振込|支払い": ["payments"],
    "領収書|レシート|証拠": ["paymentReceipts", "receipts"],
    "経費|費用|支出": ["receipts"],
    "人工|労働|工数": ["laborRecords"],  // 将来追加
    "写真|画像|画": ["photos"],
    "どうなってる|状況|進捗": ["*"],  // すべてのカテゴリ
  };
  
  Object.entries(keywordMap).forEach(([keywords, cats]) => {
    const pattern = new RegExp(keywords);
    if (pattern.test(question)) {
      categories.push(...cats);
    }
  });
  
  // 重複除去
  return [...new Set(categories)];
}
```

### 【関数5】`inferFilters(question)`

```javascript
function inferFilters(question) {
  // 質問から「条件」を推定
  
  const filters = {};
  
  // 「未請求」→ { status: "unbilled" }
  if (/未請求|請求してない|まだ|頼んでない/.test(question)) {
    filters.status = "unbilled";
  }
  
  // 「入金されてない」「未入金」→ { paymentStatus: "unpaid" }
  if (/入金されてない|未入金|支払われてない/.test(question)) {
    filters.paymentStatus = "unpaid";
  }
  
  // 「確定|承認」→ { status: "confirmed" }
  if (/確定|承認|決定/.test(question)) {
    filters.status = "confirmed";
  }
  
  // 「最新」「次」「直近」→ { sortMode: "nearest" }
  if (/最新|次|直近|一番近い/.test(question)) {
    filters.sortMode = "nearest";
  }
  
  return filters;
}
```

## 1.3 Layer 1 の出力形式

```javascript
function interpretQuestion(question) {
  return {
    // 質問の意図タイプ
    intentType: "search" | "operation" | "aggregate",
    
    // 検索条件の配列（複数の検索をまとめて実行する場合あり）
    searchIntents: [
      {
        // 【重要】この構造で、すべての質問を表現可能
        projectName: extractProjectName(question),
        customerName: extractCustomerName(question),
        dateRange: extractDateRange(question),
        categories: inferCategories(question),
        filters: inferFilters(question)
      }
    ],
    
    // 元の質問文（後の層で参照する場合あり）
    originalQuestion: question
  };
}
```

---

# 第2章 Layer 2: データ横断検索層

## 2.1 Layer 2 の責務

```
入力: SearchIntent
  ↓
projectId を特定 → 該当案件を検索
各カテゴリを検索 → フィルタリング
  ↓
出力: 統合されたデータセット
```

## 2.2 実装

```javascript
function crossSearchData(searchIntent) {
  // Step 1: projectId を特定
  let targetProjects = [];
  
  if (searchIntent.projectName) {
    // 案件名から検索
    targetProjects = findProjectsByName(searchIntent.projectName);
  } else if (searchIntent.customerName) {
    // 顧客名から検索
    targetProjects = findProjectsByCustomerName(searchIntent.customerName);
  } else if (searchIntent.dateRange?.from && !searchIntent.projectName) {
    // 日付のみの場合：全案件から日付で検索
    targetProjects = getAllProjects();
  }
  
  // Step 2: 各カテゴリで検索
  const result = {
    projects: targetProjects,
    categories: {}
  };
  
  searchIntent.categories.forEach(category => {
    result.categories[category] = [];
    
    // 【重要】すべてのカテゴリに対して同じロジック
    const allItems = localStorage[KEYS[category]] || [];
    
    allItems.forEach(item => {
      // projectId で紐付け
      if (targetProjects.some(p => p.id === item.projectId)) {
        // フィルタ条件を適用
        if (matchesFilters(item, searchIntent.filters, category)) {
          // 日付範囲でフィルタ
          if (matchesDateRange(item, searchIntent.dateRange)) {
            result.categories[category].push(item);
          }
        }
      }
    });
  });
  
  return result;
}

function matchesFilters(item, filters, category) {
  // 「未請求」フィルタ
  if (filters?.status === "unbilled" && category === "quotes") {
    const invoices = findInvoicesByQuoteId(item.id);
    return invoices.length === 0;
  }
  
  // 「未入金」フィルタ
  if (filters?.paymentStatus === "unpaid" && category === "invoices") {
    const payments = findPaymentsByInvoiceId(item.id);
    const paidAmount = sum(payments, p => p.amount);
    return paidAmount < item.amount;
  }
  
  // 「確定」フィルタ
  if (filters?.status === "confirmed") {
    return item.status === "confirmed";
  }
  
  return true;
}
```

---

# 第3章 Layer 3: 案件統合層

## 3.1 Layer 3 の責務

```
入力: 複数の検索結果
  ↓
projectId でまとめて、案件のスナップショットを構築
時系列、金銭情報、進捗を計算
  ↓
出力: projectSnapshot（1つの統合ビュー）
```

## 3.2 実装

```javascript
function buildProjectSnapshot(targetProjectId, searchResults) {
  const project = findProjectById(targetProjectId);
  const customer = findCustomerById(project.customerId);
  
  // ■ タイムラインの構築
  const timeline = buildTimeline({
    scheduleEvents: searchResults.categories.scheduleEvents,
    quotes: searchResults.categories.quotes,
    invoices: searchResults.categories.invoices,
    changeOrders: searchResults.categories.changeOrders,
    payments: searchResults.categories.payments,
    receipts: searchResults.categories.receipts,
    photos: searchResults.categories.photos,
    // 将来追加される laborRecords, purchases, deliveryNotes も同じ構造
  });
  
  // ■ 金銭情報の計算
  const financials = calcFinancials({
    quotes: searchResults.categories.quotes,
    changeOrders: searchResults.categories.changeOrders,
    invoices: searchResults.categories.invoices,
    payments: searchResults.categories.payments,
    receipts: searchResults.categories.receipts,
  });
  
  // ■ 進捗状況の判定
  const currentStage = inferStage(financials);
  
  return {
    projectId: targetProjectId,
    customer,
    project,
    timeline,           // 全イベントの時系列
    financials,         // 金銭情報
    currentStage,       // 現在の進捗（見積済/請求済/入金済/等）
    documents: {
      quotes: searchResults.categories.quotes,
      invoices: searchResults.categories.invoices,
      changeOrders: searchResults.categories.changeOrders,
    },
    expenses: {
      receipts: searchResults.categories.receipts,
    },
    photos: searchResults.categories.photos,
    // 【将来追加】新しいカテゴリのデータ
    labor: searchResults.categories.laborRecords || [],
    purchases: searchResults.categories.purchases || [],
  };
}

function buildTimeline(allData) {
  // すべてのイベントを時系列で整える
  const events = [];
  
  // scheduleEvents
  (allData.scheduleEvents || []).forEach(e => {
    events.push({
      date: e.date,
      type: "schedule",
      label: e.description,
      data: e
    });
  });
  
  // quotes
  (allData.quotes || []).forEach(q => {
    events.push({
      date: q.date,
      type: "quote",
      label: `見積 ${yen(q.amount)}`,
      data: q
    });
  });
  
  // invoices
  (allData.invoices || []).forEach(inv => {
    events.push({
      date: inv.date,
      type: "invoice",
      label: `請求 ${yen(inv.amount)}`,
      data: inv
    });
  });
  
  // payments
  (allData.payments || []).forEach(p => {
    events.push({
      date: p.date,
      type: "payment",
      label: `入金 ${yen(p.amount)}`,
      data: p
    });
  });
  
  // 【将来】laborRecords を追加
  // (allData.labor || []).forEach(l => { ... });
  
  // 【将来】purchases を追加
  // (allData.purchases || []).forEach(p => { ... });
  
  // 日付でソート
  return events.sort((a, b) => a.date.localeCompare(b.date));
}

function calcFinancials(data) {
  // 見積額合計
  const quoteAmount = sum(data.quotes || [], q => q.amount);
  
  // 追加工事額合計
  const changeOrderAmount = sum(data.changeOrders || [], c => c.amount);
  
  // 請求額合計
  const invoiceAmount = sum(data.invoices || [], inv => inv.amount);
  
  // 入金額合計
  const paidAmount = sum(data.payments || [], p => p.amount);
  
  // 未入金額
  const unpaidAmount = invoiceAmount - paidAmount;
  
  // 経費額合計
  const expenseAmount = sum(data.receipts || [], r => r.amount);
  
  return {
    quoteAmount,
    changeOrderAmount,
    invoiceAmount,
    paidAmount,
    unpaidAmount,
    expenseAmount,
    profit: invoiceAmount - expenseAmount  // 粗利（簡易版）
  };
}
```

---

# 第4章 Layer 4: 回答生成層

## 4.1 Layer 4 の責務

```
入力: projectSnapshot + 元の質問
  ↓
スナップショットから質問に関連した情報を抽出
自然言語で回答を生成
関連画面へのリンクを生成
  ↓
出力: ChatMessage { text, data, links }
```

## 4.2 実装

```javascript
function generateAnswer(originalQuestion, projectSnapshot) {
  // Step 1: 質問の意図を再確認
  // （Layer 1 で解析した searchIntent をもう一度参照）
  
  const intent = analyzeQuestionIntent(originalQuestion);
  
  // Step 2: スナップショットから情報を抽出
  const answerParts = [];
  
  // 【パターン1】「どうなってる？」→ 全体サマリー
  if (/どうなってる|状況|進捗/.test(originalQuestion)) {
    return generateProjectSummaryAnswer(projectSnapshot);
  }
  
  // 【パターン2】「いくら？」→ 金銭情報
  if (/いくら|金額|合計/.test(originalQuestion)) {
    return generateFinancialAnswer(originalQuestion, projectSnapshot);
  }
  
  // 【パターン3】「何ある？」「ある？」→ アイテムリスト
  if (/何ある|ある\?|登録/.test(originalQuestion)) {
    return generateItemListAnswer(originalQuestion, projectSnapshot);
  }
  
  // 【パターン4】「写真ある？」→ 写真の有無
  if (/写真/.test(originalQuestion)) {
    return generatePhotoAnswer(projectSnapshot);
  }
  
  // 【パターン5】「未請求」「未入金」→ ステータスベース
  if (/未請求|未入金/.test(originalQuestion)) {
    return generateStatusAnswer(originalQuestion, projectSnapshot);
  }
  
  // → すべての回答が同じ形式で返される
  return generateGenericAnswer(originalQuestion, projectSnapshot);
}

function generateProjectSummaryAnswer(projectSnapshot) {
  // 「田中邸どうなってる？」への回答例
  
  const snap = projectSnapshot;
  const fin = snap.financials;
  
  // ■ 情報が登録されているかチェック
  const hasQuote = fin.quoteAmount > 0;
  const hasInvoice = fin.invoiceAmount > 0;
  const hasPayment = fin.paidAmount > 0;
  const hasExpense = fin.expenseAmount > 0;
  const hasPhotos = (snap.photos || []).length > 0;
  
  // ■ 登録状況を明示する回答を組み立て
  let text = `${snap.project.name} の状況：`;
  
  if (hasQuote) {
    text += `\n・見積：${yen(fin.quoteAmount)}`;
  } else {
    text += `\n・見積：未登録`;
  }
  
  if (snap.financials.changeOrderAmount > 0) {
    text += `\n・追加工事：${yen(snap.financials.changeOrderAmount)}`;
  }
  
  if (hasInvoice) {
    text += `\n・請求：${yen(fin.invoiceAmount)}`;
    text += `\n・入金：${yen(fin.paidAmount)}`;
    if (fin.unpaidAmount > 0) {
      text += `（未入金：${yen(fin.unpaidAmount)}）`;
    }
  } else {
    text += `\n・請求：未登録`;
  }
  
  if (hasExpense) {
    text += `\n・経費：${yen(fin.expenseAmount)}`;
  }
  
  if (hasPhotos) {
    text += `\n・写真：${(snap.photos || []).length} 枚`;
  }
  
  // ■ 次のアクションを提案
  const nextAction = inferNextAction(snap);
  if (nextAction) {
    text += `\n\n→ 次のステップ：${nextAction}`;
  }
  
  // ■ 関連画面へのリンク
  const links = [
    {
      label: "詳細を見る",
      action: "goToProjectDetail",
      projectId: snap.projectId
    }
  ];
  
  if (nextAction?.includes("請求")) {
    links.push({
      label: "請求書を作成",
      action: "goToInvoiceForm",
      projectId: snap.projectId
    });
  }
  
  return {
    text,
    data: snap,
    links,
    sources: {
      // 「どこからこの情報を取得したか」を明示
      quotes: hasQuote,
      invoices: hasInvoice,
      payments: hasPayment,
      photos: hasPhotos,
      missing: {
        // 「どの情報が登録されていないか」も明示
        quote: !hasQuote,
        invoice: !hasInvoice,
        expense: !hasExpense
      }
    }
  };
}

function generateFinancialAnswer(originalQuestion, projectSnapshot) {
  // 「いくら？」「見積はいくら？」などの回答
  
  const fin = projectSnapshot.financials;
  let text = ``;
  
  // 質問から「何のいくら？」を判定
  if (/見積/.test(originalQuestion)) {
    if (fin.quoteAmount > 0) {
      text = `見積：${yen(fin.quoteAmount)}`;
    } else {
      text = `見積が登録されていません。`;
    }
  } else if (/請求/.test(originalQuestion)) {
    if (fin.invoiceAmount > 0) {
      text = `請求：${yen(fin.invoiceAmount)}`;
      if (fin.unpaidAmount > 0) {
        text += `\nうち未入金：${yen(fin.unpaidAmount)}`;
      }
    } else {
      text = `請求が登録されていません。`;
    }
  } else if (/経費/.test(originalQuestion)) {
    if (fin.expenseAmount > 0) {
      text = `経費：${yen(fin.expenseAmount)}`;
    } else {
      text = `経費が登録されていません。`;
    }
  } else {
    // 全体
    text = `見積：${yen(fin.quoteAmount)}\n` +
           `請求：${yen(fin.invoiceAmount)}\n` +
           `入金：${yen(fin.paidAmount)}\n` +
           `経費：${yen(fin.expenseAmount)}`;
  }
  
  return {
    text,
    data: fin,
    links: []
  };
}

function generateItemListAnswer(originalQuestion, projectSnapshot) {
  // 「写真ある？」「追加工事ある？」などの回答
  
  const snap = projectSnapshot;
  let items = [];
  let category = "";
  
  if (/写真/.test(originalQuestion)) {
    items = snap.photos || [];
    category = "写真";
  } else if (/追加工事/.test(originalQuestion)) {
    items = snap.documents.changeOrders || [];
    category = "追加工事";
  } else if (/予定/.test(originalQuestion)) {
    items = snap.timeline.filter(e => e.type === "schedule");
    category = "予定";
  }
  
  if (items.length === 0) {
    return {
      text: `${category}の登録がありません。`,
      data: null,
      links: []
    };
  }
  
  let text = `${category}：${items.length} 件`;
  // 必要に応じて詳細を追加
  
  return {
    text,
    data: { count: items.length, items },
    links: []
  };
}

function generateStatusAnswer(originalQuestion, projectSnapshot) {
  // 「未請求」「未入金」フィルタでの回答
  
  const fin = projectSnapshot.financials;
  
  if (/未請求/.test(originalQuestion)) {
    if (fin.quoteAmount > 0 && fin.invoiceAmount === 0) {
      return {
        text: `見積は済んでいますが、まだ請求されていません。`,
        data: fin,
        links: [{
          label: "請求書を作成",
          action: "goToInvoiceForm",
          projectId: projectSnapshot.projectId
        }]
      };
    }
  }
  
  if (/未入金/.test(originalQuestion)) {
    if (fin.invoiceAmount > 0 && fin.unpaidAmount > 0) {
      return {
        text: `${yen(fin.unpaidAmount)} がまだ入金されていません。`,
        data: fin,
        links: [{
          label: "入金を記録",
          action: "goToPaymentForm",
          projectId: projectSnapshot.projectId
        }]
      };
    } else if (fin.invoiceAmount === 0) {
      return {
        text: `請求がまだ登録されていません。`,
        data: fin,
        links: []
      };
    }
  }
  
  return {
    text: `登録されていません。`,
    data: null,
    links: []
  };
}
```

---

# 第5章 チャットUI統合

## 5.1 現在の renderChat() との関係

```javascript
function renderChat() {
  // 既存の UI 構造を保持
  
  const chatContainer = document.getElementById("chatContainer");
  
  // ■ 既存のチャット履歴を表示
  chatHistory.forEach(msg => {
    if (msg.isBot) {
      // Layer 4 の出力形式で表示
      displayBotMessage(msg);
    } else {
      displayUserMessage(msg.text);
    }
  });
  
  // ■ 入力フィールド + 送信ボタン
  renderChatInput();
}

function displayBotMessage(msg) {
  // Layer 4 の出力（text, data, links）を表示
  
  const messageDiv = createElement("div", "chat-message bot");
  
  // テキスト表示
  messageDiv.innerHTML = md2html(msg.text);
  
  // リンク表示（関連画面への遷移）
  if (msg.links && msg.links.length > 0) {
    const linksDiv = createElement("div", "chat-links");
    msg.links.forEach(link => {
      const btn = createButton(link.label);
      btn.onclick = () => {
        // 画面遷移
        if (link.action === "goToProjectDetail") {
          go("projectDetail", { projectId: link.projectId });
        } else if (link.action === "goToInvoiceForm") {
          go("docForm", {
            docType: "invoice",
            projectId: link.projectId
          });
        }
        // etc...
      };
      linksDiv.appendChild(btn);
    });
    messageDiv.appendChild(linksDiv);
  }
  
  chatContainer.appendChild(messageDiv);
}

function onChatSubmit(question) {
  // チャット送信時の処理
  
  // ■ ユーザーメッセージを表示
  displayUserMessage(question);
  
  // ■ Layer 1: 質問解析
  const searchIntent = interpretQuestion(question);
  
  // ■ Layer 2: データ横断検索
  const searchResults = crossSearchData(searchIntent);
  
  // ■ Layer 3: 案件統合
  const projectSnapshots = searchResults.projects.map(proj =>
    buildProjectSnapshot(proj.id, searchResults)
  );
  
  // ■ Layer 4: 回答生成
  const answer = generateAnswer(question, projectSnapshots[0]);  // 複数件の場合は工夫が必要
  
  // ■ 回答を表示
  displayBotMessage(answer);
  
  // ■ チャット履歴に保存
  chatHistory.push({ isBot: false, text: question });
  chatHistory.push({ isBot: true, ...answer });
}
```

---

# 第6章 実装順序・チェックリスト

## 6.1 実装開始前の準備

- [ ] prototype/index.html をバックアップ
  - `prototype/index.html.backup-2026-08-14` として保存
- [ ] 既存機能の動作確認（全ページ、全操作）
- [ ] メモリ・ブラウザコンソールの初期状態を記録

## 6.2 Layer 1 実装（質問解析層）

- [ ] 関数1: `extractDateRange()`
  - [ ] テスト：「今日」「明日」「先月」「8月13日」
  
- [ ] 関数2: `extractProjectName()`
  - [ ] テスト：「田中邸」「田辺さんの案件」
  
- [ ] 関数3: `extractCustomerName()`
  - [ ] テスト：「田中さん」「田辺様」
  
- [ ] 関数4: `inferCategories()`
  - [ ] テスト：各カテゴリキーワード
  
- [ ] 関数5: `inferFilters()`
  - [ ] テスト：「未請求」「未入金」「最新」
  
- [ ] `interpretQuestion()` 統合
  - [ ] SearchIntent の形式確認

## 6.3 Layer 2 実装（データ横断検索層）

- [ ] `crossSearchData()` 実装
  - [ ] projectId の特定
  - [ ] 各カテゴリの検索・フィルタリング
  
- [ ] `matchesFilters()` 実装
  - [ ] 未請求フィルタ
  - [ ] 未入金フィルタ
  - [ ] 日付範囲マッチ
  
- [ ] テスト：複数のカテゴリを同時検索

## 6.4 Layer 3 実装（案件統合層）

- [ ] `buildProjectSnapshot()` 実装
  
- [ ] `buildTimeline()` 実装
  - [ ] 全イベントの時系列整列
  
- [ ] `calcFinancials()` 実装
  - [ ] 見積・請求・入金・経費の合計
  - [ ] 利益計算
  
- [ ] テスト：スナップショットの完全性確認

## 6.5 Layer 4 実装（回答生成層）

- [ ] `generateProjectSummaryAnswer()` 実装
- [ ] `generateFinancialAnswer()` 実装
- [ ] `generateItemListAnswer()` 実装
- [ ] `generateStatusAnswer()` 実装
- [ ] テスト：回答の自然言語化

## 6.6 チャットUI統合

- [ ] `displayBotMessage()` に Layer 4 出力を対応
- [ ] リンク（画面遷移）の実装
- [ ] `onChatSubmit()` 全層の統合

## 6.7 テスト（15+ 質問パターン）

- [ ] 「今日何ある？」
- [ ] 「8月13日何買った？」
- [ ] 「田中邸どうなってる？」
- [ ] 「田中さんの案件は？」
- [ ] 「まだ請求してない案件ある？」
- [ ] 「入金されてないものある？」
- [ ] 「田中邸の見積はいくら？」
- [ ] 「田中邸の追加工事は？」
- [ ] 「先月の請求は？」
- [ ] 「佐藤さんにいくら請求した？」
- [ ] 「この案件の経費は？」
- [ ] 「このレシートはどの案件？」
- [ ] 「田中邸の写真ある？」
- [ ] 「今日の予定と買い出しをまとめて」
- [ ] その他新規パターン

## 6.8 既存機能との互換性確認

- [ ] 顧客・案件作成
- [ ] 見積書作成
- [ ] 請求書作成
- [ ] 入金記録
- [ ] レシート撮影・経費登録
- [ ] 予定登録
- [ ] 写真アップロード
- [ ] 既存チャット履歴（モジュール変数）の保持

---

# 第7章 セキュリティ・课金確認チェック

## ✅ 許可（報告不要）

- [x] 既存コードの修正（Layer 1-4 追加）
- [x] 既存データ構造の整理（共通プロパティ定義）
- [x] ローカル完結のJS処理
- [x] UI改善（チャット画面更新）
- [x] 既存機能の統合（Layer と既存 UI の接続）
- [x] テスト
- [x] リファクタリング

## ❌ 禁止（実装前に報告・確認）

- [ ] Claude API・外部LLM導入
- [ ] Supabase等の外部DB導入
- [ ] 認証サービス導入
- [ ] Netlify Functions導入
- [ ] 有料API導入
- [ ] 顧客情報の外部送信
- [ ] APIキーのフロント埋め込み

## 🚨 実装中に判明した場合は停止・報告

このドキュメント策定時点では、上記の禁止項目は必要ではありません。
Layer 1-4 はすべて localStorage で完結可能です。

---

# 第8章 AI導入時の変更計画（参考）

**重要**：Phase 1 では実装しません。将来のAI導入時の参考情報です。

```javascript
// 【現在】ルールベース版
function interpretQuestion_v1(question) {
  // 正規表現・キーワード → SearchIntent
  return { searchIntents: [...] };
}

// 【Phase 2】AI版（実装時に置き換え）
async function interpretQuestion_v2(question) {
  // Claude API（Netlify Functions経由）に「自然言語 → SearchIntent」を依頼
  const response = await fetch("/.netlify/functions/interpret-question", {
    method: "POST",
    body: JSON.stringify({ question, context: projectMetadata })
  });
  return response.json();
}

// ■ 置き換え場所：onChatSubmit() 内の1行のみ
function onChatSubmit(question) {
  // const searchIntent = interpretQuestion_v1(question);  // ← ここを
  const searchIntent = await interpretQuestion_v2(question);  // ← これに変更
  
  // 以下、Layer 2-4 は変わらない
  const searchResults = crossSearchData(searchIntent);
  // ...
}
```

---

# 付録A: データモデル仕様（共通フィールド）

すべてのデータ型が以下を持つ：

```javascript
{
  // ID
  id: string,              // UUID等のユニークID
  projectId: string,       // ← 【重要】全データの中心
  
  // タイムスタンプ
  date: string,            // ISO形式 "2026-08-14"
  createdAt: string,       // ISO形式 "2026-08-14T10:30:00Z"
  
  // 金額（金銭データの場合）
  amount?: number,         // 金額（JPY）
  currency?: string,       // デフォルト "JPY"
  
  // 分類
  category?: string,       // カテゴリ（「大工」「電気」等）
  type: string,            // データ型（"quote", "invoice", etc）
  status?: string,         // ステータス（"draft", "confirmed", "archived"）
  
  // テキスト
  description?: string,    // 説明
  notes?: string,          // メモ
}
```

各カテゴリ固有のフィールドは、上記に加えて定義。

---

# 付録B: 変更が必要な既存コード（参考）

- `renderChat()` → Layer 4 の出力に対応
- `bindEvents()` → チャット送信イベント + Layer 1-4 呼び出し
- 必要に応じて、日付フォーマッタ等のユーティリティを共通化

---

# 付録C: 実装完了後の報告テンプレート

実装完了時に以下を報告します：

1. **何を変更したか**
   - ファイル：prototype/index.html
   - 追加行数：XXX行
   - 修正関数：Layer 1-4 実装 + UI統合

2. **何ができるようになったか**
   - 実装した質問パターン一覧
   - 各質問への回答例

3. **既存機能への影響確認**
   - 全テスト結果（✅ 全機能動作確認）

4. **未実装のもの**
   - laborRecords, purchases, deliveryNotes（将来追加）
   - OperationIntent（将来実装）
   - AI導入（Phase 2）

5. **セキュリティ・課金変更の確認**
   - ❌ 変更なし確認（APIキー なし、外部通信 なし、課金 なし）

6. **AI追加時の変更点**
   - `interpretQuestion()` 関数のみ置き換え可能
   - Layer 2-4 は修正不要
   - Netlify Functions を新規作成して Claude API を呼び出す設計

---

# 終了
