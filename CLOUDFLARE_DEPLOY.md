# نشر تطبيق الأدمن على Cloudflare Pages (ربط GitHub — مضمون)

> الرفع المباشر بـ `wrangler` من جهازك بيفشل بسبب timeout في الشبكة لـ endpoint بتاع Cloudflare.
> الحل: خلي Cloudflare يبني من GitHub على سيرفراته.

## الخطوات

1. https://dash.cloudflare.com → **Workers & Pages**
2. المشروع `euro-trade-admin` موجود → افتحه → **Settings → Builds & deployments**
   - أو **Create application → Pages → Connect to Git**
3. اربط GitHub واختار الريبو: **eurotrd1-beep/euro_trade_admin**
4. إعدادات البناء:
   - **Framework preset:** None
   - **Build command:**
     ```
     git clone https://github.com/flutter/flutter.git --depth 1 -b stable && export PATH="$PATH:$(pwd)/flutter/bin" && flutter build web --release
     ```
   - **Build output directory:** `build/web`
   - **Root directory:** (فاضية)
5. **Save and Deploy**

الرابط: `https://euro-trade-admin.pages.dev`

## بديل (رفع مباشر من شبكة تانية)
```
npx wrangler pages deploy build/web --project-name=euro-trade-admin --branch=main --commit-dirty=true
```
