// Supabase Edge Function: ai-structure
//
// 役割：「話す・入力」で話した/書いた生のテキストを、Claude API(Haiku)に渡して
// 構造化データ(日付・時間・顧客・案件など)と、自然な日本語の要約を作らせる。
//
// セキュリティ上のポイント：
// - AnthropicのAPIキーは、このファイル(サーバー側)にだけ置く。クライアント(index.html)
//   には一切含めないので、アプリを使う人やGitHub(Public)から見られることはない。
// - このFunctionはSupabaseの標準機能で「ログイン済みユーザーのみ呼び出せる」設定
//   (JWT検証)がデフォルトで有効。ログインしていない第三者が勝手に呼び出して
//   まなみさんのAPI利用料を消費する、ということは基本的に防げる。
// - 呼び出しに失敗しても、アプリ側(index.html)は無料のキーワード抜き出しに
//   自動で切り替わる作りなので、この機能が止まってもアプリ自体は止まらない。
//
// デプロイ方法は「AI要約機能デプロイ手順.md」を参照してください。

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SYSTEM_PROMPT = `あなたは建築業の一人親方が音声入力したメモを構造化するアシスタントです。
入力は音声認識によるテキストのため、誤変換や聞き取りミスが含まれることがあります。

次のJSON形式で「のみ」出力してください。説明文やコードブロックの記号(\`\`\`など)は一切付けないでください。

{
  "date": "文中の日付をそのままの表現で（例:「8月20日」「明日」）。分からなければnull",
  "time": "文中の時刻をそのままの表現で（例:「9時」）。分からなければnull",
  "customer": "顧客名（「〜さん」「〜工務店」等）。分からなければnull",
  "project": "案件名（「〜邸」等）。分からなければnull",
  "workLocation": "現場の場所。文中に明記されていなければnull",
  "periodStart": "工期の開始日をYYYY-MM-DD形式で。年の言及が無ければ2026年とみなす。期間の言及が無ければnull",
  "periodEnd": "工期の終了日をYYYY-MM-DD形式で。無ければnull",
  "content": "内容を簡潔に要約した自然な日本語（1〜3行程度）。日時・場所・やるべきことが分かるように書く。複数の予定が含まれる場合は改行で区切って箇条書き風にする",
  "tasks": "買い物や準備などの関連タスクがあれば簡潔に。無ければnull"
}

重要なルール：
- 文章から読み取れない・自信が無い項目は、絶対に推測せず null にしてください
- 音声認識の誤変換で意味が取れない箇所は、content の中に「（聞き取れず不明）」のように残してください。分かったふりをして勝手に補完しないでください
- JSON以外の文字は一切出力しないでください`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => null);
    const rawText = body && typeof body.rawText === "string" ? body.rawText.trim() : "";
    if (!rawText) {
      return new Response(JSON.stringify({ error: "rawTextが必要です" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    // 極端に長い入力でコストが跳ねないよう安全のため上限を設ける
    const trimmedRaw = rawText.slice(0, 4000);

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "サーバー側にAPIキーが設定されていません" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 700,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: trimmedRaw }],
      }),
    });

    if (!anthropicRes.ok) {
      const errText = await anthropicRes.text();
      return new Response(JSON.stringify({ error: "AI呼び出しに失敗しました: " + errText }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const data = await anthropicRes.json();
    const text = (data.content || [])
      .filter((b: any) => b.type === "text")
      .map((b: any) => b.text)
      .join("\n");

    let parsed: unknown;
    try {
      // 稀にコードブロックで囲われて返ってくる場合に備えて、念のため除去してから解析する
      const cleaned = text.trim().replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```\s*$/i, "");
      parsed = JSON.parse(cleaned);
    } catch (_e) {
      return new Response(JSON.stringify({ error: "AIの応答を解析できませんでした" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ structured: parsed }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e && (e as Error).message) || e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
