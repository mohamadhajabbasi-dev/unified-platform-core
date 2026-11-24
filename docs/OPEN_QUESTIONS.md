# OPEN_QUESTIONS — شواهد لازم، بدون تغییر تصمیم مصوب
Action INV-002 | 2026-11-24
- Q-001 (مسدودکننده): آیا ERPPlus عملیاتی واقعاً SQL Server است؟ کد pinned از UseSqlServer استفاده می‌کند؛ MySQL سند اولیه بر اساس گفته مالک بوده. موتور/نسخه و نام دیتابیس از metadata مجاز تأیید شود؛ سپس در صورت نیاز اصلاح سند با تأیید مالک.
- Q-002 (مسدودکننده): هر دو دستگاه Remote Desktop Commander آفلاین. یک دستگاه مجازِ متصل به دیتابیس یا خروجی metadata پاک‌سازی‌شده لازم است؛ نه credential، dump یا اطلاعات مشتری.
- Q-003: mapping دقیق tenant/store/branch/company و tenantهای دارای چند Store؛ uniqueness فعلی Commerce در سطح Store، الزام هدف در سطح Tenant.
- Q-004: Customer vs BusinessPartner و legacy aliases؛ verified phone/email، برخوردهای ambiguous، soft-delete و concurrent upsert؛ هیچ merge خودکار پیش از تأیید.
- Q-005: ownership فیلدی محصول/محتوا/قیمت؛ تفاوت variant و SKU؛ stock ledger vs balance، reservations، warehouses و واحد/ارز.
- Q-006: ارتباط order/invoice/payment/refund/cheque، external IDs و idempotency؛ حفظ سندهای مالی.
- Q-007: RLS واقعی، PK/FK/index/trigger/job/view/grants/حجم و نسخه deployed؛ انطباق با کد pinned.
- Q-008: فعال بودن workerها و webhookها، مسیرهای تمام کانال‌ها، بکاپ/restore و بار واقعی؛ پیش‌نیاز طراحی نهایی.
- Q-009: آرشیو PDF/PNG/ZIP اولیه اختیاری و معوق؛ فاقد اثر روی فاز inventory.
تصمیمات D-001..D-011 و O-001..O-007 بدون تغییر باقی می‌مانند.
