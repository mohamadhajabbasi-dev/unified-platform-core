# NEXT_ACTIONS — مراحل بعدی به ترتیب

1. تأیید اینکه اسناد اولیه و گزارش اقدامات به مخزن خصوصی commit شده‌اند؛ بررسی SHA و فهرست فایل‌ها.
2. در صورت لزوم اضافه‌کردن فایل‌های binary PDF/نمودار به مخزن فقط پس از بررسی privacy و ممنوعیت داده حساس. صرف وجود فایل در ZIP به معنی push آن نیست.
3. گرفتن تأیید مالک برای **صرفاً بررسی read-only** و دسترسی امن به سرویس‌های موجود.
4. دریافت اطلاعات نسخه MySQL/PostgreSQL، schema، table، PK/FK، index، trigger، job، view، حجم داده، mapping و منبع حقیقی هر موجودیت؛ بدون داده محرمانه.
5. ترسیم نقشه producer/consumer در ERPPlus، CommerceAI، storefront، اپ موبایل، CRM، پیام‌رسان‌ها، agentها و taskهای sync.
6. تولید `docs/CURRENT_INVENTORY.md`، `docs/CURRENT_DATA_MAP.md`، `docs/CURRENT_SYNC_MAP.md` و `docs/OPEN_QUESTIONS.md` با شواهد.
7. نوشتن ADR و ERD نهایی برای بررسی و تأیید، **بدون ایجاد جدول یا تغییر تولید**.
8. بعد از تأیید طراحی، staging و تست مهاجرت و بازگشت مطابق MASTER_PLAN.

**بعد از هر اقدام**: WORK_LOG append، PROJECT_STATE و NEXT_ACTIONS به‌روز، و commit ثبت شود. از کار تکراری جلوگیری کن؛ پیش از هر عمل، وضعیت فعلی را دوباره بررسی کن.

## Current checkpoint INV-001 — supersedes items 1–3 status above
- [x] Verify initial GitHub files and commit history (starting HEAD `503273567150bcf85893723085b145718956db37`).
- [ ] Optional archive: deferred; not a prerequisite for read-only inventory.
- [x] Owner authorizes read-only discovery in current request; actual secure access still unverified.
- [ ] First exact action: discover authorized ERPPlus/CommerceAI source repositories and available read-only DB connection or sanitized metadata exports. Confirm target engines/databases and scope before querying; no production changes, no secrets/PII. Then proceed with items 4–8 in order. Do not create tables/code or finalize mappings without evidence and owner approval.
