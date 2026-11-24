# معماری مفهومی — نمودار قابل نسخه‌بندی

این چارت صرفاً conceptual است و جایگزین ERD واقعی مبتنی بر schema موجود نمی‌شود.

```mermaid
flowchart TB
  SA["مدیر کل / کنترل سراسری حسابرسی‌شده"] --> Staff["کارکنان پلتفرم / نقش و دسترسی محدود"]
  SA --> Approval["تأیید ماژول و مجوز"]
  Approval --> TA["تننت A / مدیر و کاربران"]
  Approval --> TB["تننت B / مدیر و کاربران"]
  Staff --> IAM["هویت و مجوز / Tenant Scope / RLS"]
  TA --> IAM
  TB --> IAM
  IAM --> Gateway["سرویس و API امن مرکزی"]
  ERP["ERPPlus"] --> Gateway
  COM["Commerce"] --> Gateway
  Apps["اپ موبایل / CRM / پیام‌رسان‌ها / برنامه‌های آینده"] --> Gateway
  Gateway --> DB["CentralDB: یک PostgreSQL فیزیکی"]
  DB --> Customer["Customers + TenantCustomers + Contacts"]
  DB --> Product["Products + TenantProducts + TenantPrices + Inventory"]
  DB --> Orders["Orders + OrderItems + Payments"]
  DB --> Accounting["حسابداری تننتی + درآمد پلتفرم"]
  DB --> Ops["Audit + Metrics + Alerts + Tenant Backup Jobs"]
```

نکته: فلش‌های نمایشی به معنی اتصال آزاد مستقیم کاربران/برنامه‌ها به DB نیستند. همه عملیات به سرویس مرکزی و احراز هویت محدود است. نسخه اولیه داده‌های فعلی: ERPPlus/MySQL و Commerce/PostgreSQL؛ انتقال فقط پس از بررسی و تأیید.
