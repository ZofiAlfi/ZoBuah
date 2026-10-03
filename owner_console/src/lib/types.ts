export type Owner = {
  id: string;
  username: string;
  full_name: string;
  created_at: string | null;
};

export type AdminToken = {
  access_token: string;
  refresh_token: string;
  token_type: string;
  owner: Owner;
};

export type Plan = "TRIAL" | "BASIC" | "PRO" | "UNLIMITED";
export type StoreStatus = "ACTIVE" | "SUSPENDED" | "EXPIRED";
export type Health = "OK" | "STALE" | "DEAD";

export type StoreListItem = {
  id: string;
  code: string;
  name: string;
  owner_name: string;
  phone: string | null;
  address: string | null;
  plan: Plan;
  plan_expires_at: string | null;
  days_to_expiry: number | null;
  status: StoreStatus;
  is_active: boolean;
  health: Health;
  last_sync_at: string | null;
  user_count: number;
  product_count: number;
  sale_count_30d: number;
  revenue_30d: number;
  created_at: string | null;
};

export type StoreDetail = StoreListItem & {
  device_count: number;
  category_count: number;
  low_stock_count: number;
  pending_damage_count: number;
  failed_sync_count_7d: number;
  total_sales: number;
  lifetime_revenue: number;
};

export type Overview = {
  total_stores: number;
  active_stores: number;
  suspended_stores: number;
  expired_stores: number;
  trial_stores: number;
  total_users: number;
  total_products: number;
  total_devices: number;
  total_sales_30d: number;
  revenue_30d: number;
  profit_30d: number;
  avg_revenue_per_store_30d: number;
  healthy_stores: number;
  stale_stores: number;
  dead_stores: number;
  pending_damage_total: number;
  expiring_soon: number;
  generated_at: string;
};

export type RevenuePoint = {
  date: string;
  revenue: number;
  modal: number;
  profit: number;
  transactions: number;
};

export type TopStore = {
  store_id: string;
  code: string;
  store_name: string;
  revenue: number;
  profit: number;
  transactions: number;
};

export type PlanRow = {
  plan: Plan;
  store_count: number;
  active_store_count: number;
  expired_count: number;
  revenue_30d: number;
};

export type StoreUsage = {
  store_id: string;
  code: string;
  store_name: string;
  plan: Plan;
  user_count: number;
  product_count: number;
  category_count: number;
  device_count: number;
  sale_count_30d: number;
  revenue_30d: number;
  last_sync_at: string | null;
  health: Health;
};

export type HealthRow = {
  store_id: string;
  code: string;
  store_name: string;
  health: Health;
  last_sync_at: string | null;
  hours_since_sync: number | null;
  device_count: number;
  failed_sync_7d: number;
};

export type Alert = {
  code: string;
  severity: "CRITICAL" | "WARNING" | "INFO";
  title: string;
  message: string;
  store_id: string | null;
  store_name: string | null;
  created_at: string | null;
};

export type AdminUser = {
  id: string;
  username: string;
  full_name: string;
  role: "BOS" | "KARYAWAN";
  is_active: boolean;
  store_id: string | null;
  store_name: string | null;
  created_at: string | null;
};

export type Broadcast = {
  id: string;
  title: string;
  body: string;
  level: "INFO" | "WARNING" | "MAINTENANCE";
  target: "ALL" | "STORE";
  store_id: string | null;
  store_name: string | null;
  starts_at: string;
  expires_at: string | null;
  is_active: boolean;
  created_by: string | null;
  created_at: string;
};

export type AuditLog = {
  id: string;
  user_id: string | null;
  username: string | null;
  store_id: string | null;
  store_name: string | null;
  action: string;
  entity_type: string | null;
  entity_id: string | null;
  details: string | null;
  ip_address: string | null;
  created_at: string | null;
};

export type ImpersonateResult = {
  access_token: string;
  token_type: string;
  read_only: boolean;
  expires_in_minutes: number;
  store: StoreListItem | { id: string; code: string; name: string };
};

export type PageMeta = {
  page: number;
  page_size: number;
  total: number;
  total_pages: number;
};

export type StoreProductLite = {
  id: string;
  store_id: string | null;
  name: string;
  category_name: string | null;
  unit: string;
  modal_price: number;
  selling_price: number;
  stock: number;
  is_active: boolean;
};

export type AdminSale = {
  id: string;
  store_id: string | null;
  transaction_number: string;
  employee_id: string;
  employee_name: string | null;
  total_amount: number;
  total_modal: number;
  total_profit: number;
  discount: number;
  status: "COMPLETED" | "CANCELED";
  canceled_at: string | null;
  canceled_by: string | null;
  canceled_reason: string | null;
  created_at: string | null;
  updated_at: string | null;
  item_count: number;
};

export type SaleItemLite = {
  id: string;
  sale_id: string;
  product_id: string;
  product_name: string;
  unit: string;
  unit_price: number;
  modal_price: number;
  quantity: number;
  subtotal: number;
};

export type SalePaymentLite = {
  id: string;
  sale_id: string;
  method: "CASH" | "TRANSFER" | "QRIS";
  amount: number;
  cash_received: number | null;
  change_amount: number | null;
  reference: string | null;
  file_url: string | null;
};

export type EditLogEntry = AuditLog;

export type AdminSaleDetail = AdminSale & {
  items: SaleItemLite[];
  payment: SalePaymentLite | null;
  edit_history: EditLogEntry[];
};

export type DashboardPayload = {
  overview: Overview;
  revenue_30d: RevenuePoint[];
  top_stores: TopStore[];
  plans: PlanRow[];
  alerts: Alert[];
};

export type Paged<T> = { items: T[]; meta: PageMeta };

/* ------------------------------------------------------------------ */
/* Data Browser per toko                                              */
/* ------------------------------------------------------------------ */

export type DamageStatus = "PENDING" | "APPROVED" | "REJECTED";

export type DamageReport = {
  id: string;
  store_id: string | null;
  product_id: string | null;
  product_name: string | null;
  quantity: number;
  unit: string;
  qty_in_base_unit: number | null;
  reason: string;
  description: string | null;
  status: DamageStatus;
  employee_id: string | null;
  employee_name: string | null;
  approved_by_name: string | null;
  approved_at: string | null;
  rejected_by_name: string | null;
  rejected_at: string | null;
  rejection_reason: string | null;
  photos: string[];
  created_at: string | null;
};

export type DamageSummary = {
  total: number;
  pending: number;
  approved: number;
  rejected: number;
};

export type StockMovement = {
  id: string;
  product_id: string | null;
  product_name: string | null;
  movement_type: string;
  quantity: number;
  stock_before: number;
  stock_after: number;
  reference_type: string | null;
  notes: string | null;
  user_name: string | null;
  created_at: string | null;
};

export type StockSummary = {
  total_movements: number;
  in: number;
  out: number;
  sale: number;
  opening: number;
  adjustment: number;
  damage: number;
};

export type Payment = {
  id: string;
  sale_id: string | null;
  transaction_number: string | null;
  method: "CASH" | "TRANSFER" | "QRIS";
  amount: number;
  cash_received: number | null;
  change_amount: number | null;
  reference: string | null;
  file_url: string | null;
  employee_name: string | null;
  sale_status: "COMPLETED" | "CANCELED" | null;
  created_at: string | null;
};

export type PaymentSummary = {
  total_amount: number;
  total_payments: number;
  by_method: Record<string, number>;
};

export type ProductHistoryEntry = {
  id: string;
  action: string;
  product_id: string | null;
  product_name: string | null;
  details: Record<string, unknown> | null;
  user_name: string | null;
  ip_address: string | null;
  created_at: string | null;
};

export type StoreCategory = {
  id: string;
  name: string;
  description: string | null;
  is_active: boolean;
  product_count: number;
  created_at: string | null;
};

/* Tiga endpoint terakhir memakai Paged polos; tiga pertama menambah
 * summary. Bentuk summary berbeda per tab, jadi field-nya dibiarkan
 * generik supaya satu DataTable bisa dipakai untuk semuanya. */
export type PagedWithSummary<T, S> = { items: T[]; meta: PageMeta; summary: S };
