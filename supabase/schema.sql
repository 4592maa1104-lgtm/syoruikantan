-- ============================================================
-- Supabase移行 Phase 0: テーブル・RLSポリシー・Storageバケット作成
-- ============================================================
-- 実行方法: Supabaseダッシュボード > SQL Editor に貼り付けて実行してください。
--
-- 設計方針（合意済み）:
--   - 単一テナント（このアプリを使うのは実質1事業者）
--   - RLS: 認証済み(authenticated)ユーザーのみ読み書き可。行ごとの所有者管理はしない
--   - ログインアカウントは自分専用の1つのみ（サインアップ画面は作らない。
--     アカウントは Authentication > Users > Add user から手動作成してください）
--   - 画像は Storage バケット + パス参照方式（DB列には直接base64を入れない）
--   - IDは既存アプリのID形式（例: "cust_1234567890_ab12cd"）をそのまま text主キーとして使う
--     （二重保存フェーズでlocalStorageと同じIDのまま両方に書き込めるようにするため、UUID化しない）
--   - チャット履歴は今回のスコープ外（テーブルを作らない）
-- ============================================================

-- ---- 顧客 ----
create table public.customers (
  id text primary key,
  name text not null,
  address text,
  tel text,
  contact_person text,
  created_at timestamptz not null default now()
);

-- ---- 案件 ----
create table public.projects (
  id text primary key,
  customer_id text references public.customers(id),
  name text,
  work_location text,
  period_start date,
  period_end date,
  stage text check (stage in ('見積前','見積中','受注','工事中','完了')),
  created_at timestamptz not null default now()
);

-- ---- 見積書＋追加見積書（parent_quote_idで区別） ----
-- invoice_id列のFK制約は、invoicesテーブル作成後に別途ALTER TABLEで追加する（循環参照のため）
create table public.quotes (
  id text primary key,
  project_id text references public.projects(id),
  doc_number text,
  issue_date date,
  customer_name text,      -- スナップショット（顧客名変更後も当時の名前を保持）
  project_name text,       -- 件名（自由テキスト。projects.nameとは別概念）
  work_location text,
  period_start date,
  period_end date,
  due_date date,
  due_date_note text,
  items jsonb,             -- [{category,spec,qty,unit,unitPrice}, ...]
  remarks text,
  payment_terms text,
  parent_quote_id text references public.quotes(id),  -- 追加見積書のみ設定
  approval_status text check (approval_status in ('pending','approved')),  -- 追加見積書のみ
  billed boolean not null default false,  -- 追加見積書が請求に組み込まれたか
  invoice_id text,  -- FKは後段のALTER TABLEで付与
  created_at timestamptz not null default now()
);

-- ---- 請求書 ----
create table public.invoices (
  id text primary key,
  project_id text references public.projects(id),
  doc_number text,
  issue_date date,
  customer_name text,
  project_name text,
  work_location text,
  period_start date,
  period_end date,
  due_date date,
  due_date_note text,
  items jsonb,
  remarks text,
  payment_terms text,
  quote_id text references public.quotes(id),  -- 元見積
  payment_status text,      -- 旧式の簡易ステータス（後方互換のため保持）
  paid_date date,
  change_order_ids jsonb,       -- 請求に含めた追加工事ID配列（既存JS構造をそのまま反映）
  additional_quote_ids jsonb,   -- 請求に含めた追加見積書ID配列
  created_at timestamptz not null default now()
);

-- quotes.invoice_id の外部キー制約をここで付与（invoicesテーブル作成後）
alter table public.quotes
  add constraint quotes_invoice_id_fkey foreign key (invoice_id) references public.invoices(id);

-- ---- 領収書（発行書類） ----
create table public.payment_receipts (
  id text primary key,
  project_id text references public.projects(id),
  doc_number text,
  issue_date date,
  customer_name text,
  project_name text,
  amount_received numeric,
  description text,
  invoice_id text references public.invoices(id),
  created_at timestamptz not null default now()
);

-- ---- 追加工事（軽量版・説明文＋金額のみ） ----
create table public.change_orders (
  id text primary key,
  project_id text references public.projects(id) not null,
  description text,
  amount numeric,
  billed boolean not null default false,
  invoice_id text references public.invoices(id),
  created_at timestamptz not null default now()
);

-- ---- 入金記録 ----
create table public.payments (
  id text primary key,
  invoice_id text references public.invoices(id) not null,
  amount numeric,
  date date,
  note text,
  created_at timestamptz not null default now()
);

-- ---- 経費・レシート（撮影） ----
-- image_url は Supabase Storage 上のパス（バケット: app-images）を保存する
create table public.expense_receipts (
  id text primary key,
  project_id text references public.projects(id),
  image_url text,
  store text,
  amount numeric,
  date date,
  project_name text,
  category text,
  created_at timestamptz not null default now()
);

-- ---- 現場写真 ----
create table public.photos (
  id text primary key,
  project_id text references public.projects(id) not null,
  image_url text,
  phase text check (phase in ('着工前','施工中','完了','追加工事')),
  caption text,
  created_at timestamptz not null default now()
);

-- ---- 予定 ----
create table public.schedule_events (
  id text primary key,
  project_id text references public.projects(id) not null,
  title text,
  date date,
  start_time text,   -- "9:00"のような自由テキストのままtime型にしない（既存仕様を踏襲）
  attendees text,
  created_at timestamptz not null default now()
);

-- ---- 話す入力メモ ----
create table public.captures (
  id text primary key,
  project_id text references public.projects(id),
  raw_text text,
  structured jsonb,
  confirmed jsonb,
  status text,
  created_at timestamptz not null default now()
);

-- ---- よく使う工事項目 ----
create table public.item_presets (
  id text primary key,
  category text,
  spec text,
  unit text
);

-- ---- 自社情報（常に1行のみ） ----
create table public.company_profile (
  id text primary key default 'default',
  name text,
  zip text,
  address text,
  tel text,
  fax text,
  invoice_reg_no text,
  bank_name text,
  bank_branch text,
  account_type text,
  account_number text,
  account_holder text
);

-- ============================================================
-- RLS（Row Level Security）
-- 方針: 認証済みユーザーのみ全操作可。未ログイン(anon)は一切アクセス不可。
-- 行ごとの所有者管理はしない（単一テナントのため auth.role() のみで判定）
-- ============================================================

alter table public.customers        enable row level security;
alter table public.projects         enable row level security;
alter table public.quotes           enable row level security;
alter table public.invoices         enable row level security;
alter table public.payment_receipts enable row level security;
alter table public.change_orders    enable row level security;
alter table public.payments         enable row level security;
alter table public.expense_receipts enable row level security;
alter table public.photos           enable row level security;
alter table public.schedule_events  enable row level security;
alter table public.captures         enable row level security;
alter table public.item_presets     enable row level security;
alter table public.company_profile  enable row level security;

create policy "authenticated_full_access" on public.customers
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.projects
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.quotes
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.invoices
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.payment_receipts
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.change_orders
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.payments
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.expense_receipts
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.photos
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.schedule_events
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.captures
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.item_presets
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated_full_access" on public.company_profile
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- ============================================================
-- Storage（画像バケット）
-- 経費レシート・現場写真の画像を保存する専用バケットを作成し、
-- 同じくauthenticatedのみ読み書き可能にする。
-- ============================================================

insert into storage.buckets (id, name, public)
values ('app-images', 'app-images', false)
on conflict (id) do nothing;

create policy "authenticated_full_access_storage" on storage.objects
  for all
  using (bucket_id = 'app-images' and auth.role() = 'authenticated')
  with check (bucket_id = 'app-images' and auth.role() = 'authenticated');
