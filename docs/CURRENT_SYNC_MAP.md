# CURRENT_SYNC_MAP — مسیرهای مشاهده‌شده در کد (PARTIAL)
Action INV-002 | 2026-11-24
| Producer | Consumer | مسیر | شواهد |
|---|---|---|---|
| ERPPlus | CommerceAI | GET /api/public/commerce/products | PullCatalogAsync، upsert Product/Variant/StoreProductVariant؛ sync image jobs |
| ERPPlus | CommerceAI | GET /api/public/commerce/inventory | PullInventoryAsync، update listing stock |
| CommerceAI | ERPPlus | POST /api/public/commerce/customers/upsert | PushCustomersAsync و UpsertCustomer؛ لینک ErpPlusCustomerId |
| CommerceAI | ERPPlus | POST /api/public/commerce/sales | PushOrdersAsync برای Confirmed/Fulfilled یا دارای Paid payment، غیر Cancelled و non-Synced؛ حداکثر 50 در batch |
| ERPPlus | CommerceAI | GET /api/public/commerce/contact-channels | PullContactChannelsAsync |
| ERPPlus endpoint | مصرف‌کننده هنوز نامعلوم | PUT /api/public/commerce/products/{productId}/price؛ POST .../images/replace؛ PUT .../inventory-webhook | endpoint وجود دارد؛ caller/live activation تأیید نشده |

[ERP controller](https://github.com/mohamadhajabbasi-dev/ERPPlus/blob/52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049/ERPPlus.Api/Controllers/CommerceSyncController.cs) / [Commerce sync service](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/Integrations/ErpPlusSyncService.cs) / [Commerce sync worker](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/Integrations/ErpPlusSyncWorker.cs) / [DI registration](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/DependencyInjection.cs#L185).

Worker در کد hosted service ثبت شده، initial delay 20s و delay 1min در حلقه؛ اجرای عملیاتی/زمان‌بندی واقعی و تنظیمات هر Store نامعلوم. مسیرها قابلیت‌های موجود در کدند نه ادعای فعال بودن. مدل Commerce دارای EF query filters با tenant/store context است؛ RLS فیزیکی اثبات نشده. IgnoreQueryFilters در sync مشاهده شد؛ فیلترهای explicit و سایر callerها باید حسابرسی شوند. [Context](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/Persistence/ApplicationDbContext.cs#L125-L206).

باقی‌مانده: endpointهای دیگر، فروش حضوری، webhook caller/receiver، storefront، اپ، CRM و پیام‌رسان‌ها، agentها، schedulerها و وضعیت فعال production. هیچ sync/service غیرفعال یا تغییر نکرده.
