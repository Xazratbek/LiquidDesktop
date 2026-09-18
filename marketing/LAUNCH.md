# Liquid Desktop — launch kit

## Fayllar

| Fayl | Nima uchun |
|---|---|
| `marketing/reel-9x16.mp4` | Instagram Reels / TikTok / YouTube Shorts (15 s, yozuvli, oxirida narx kartasi) |
| `marketing/hero-16x9.mp4` | X (Twitter), Product Hunt, YouTube |
| `site/` | Landing sahifa (statik — istalgan hostingga yuklanadi) |
| `.dist/Liquid Desktop.dmg` | Xaridorga yuboriladigan fayl |

Reel ovozsiz. Instagram’da yuklashda trenddagi audio qo‘shing — bu reach uchun muhim.

## 1. Eng kuchli video: haqiqiy MacBook

3D animatsiya tushuntiradi, lekin **viral bo‘ladigani — telefon bilan olingan haqiqiy kadr**. 20 daqiqa ajrating:

1. Qorong‘iroq xona, MacBook ekran yorqinligi maksimal, Lagoon mavzusi, "Amount of water" ko‘proq.
2. Telefonni shtativga qo‘ying, kadrda faqat ekran va qo‘l.
3. Kadrlar (har biri 2–4 s):
   - Qopqoqni sekin orqaga yotqizish → suv ekran bo‘ylab ko‘tariladi.
   - Qopqoqni tez qimirlatish → to‘lqin va tomchilar.
   - Sichqonchani suvdan o‘tkazish.
   - ⌃⌥⌘T bilan Mercury → Lava almashishi.
4. Birinchi 1 soniyada harakat bo‘lsin (kirish sekin bo‘lsa odam o‘tib ketadi).

## 2. Post matnlari

**Hook variantlari** (videoning birinchi soniyasidagi yozuv yoki izohning birinchi qatori):

- What if your Mac was full of water? 💧
- I made my MacBook screen an aquarium
- Tilt your laptop. The water follows.
- POV: your desktop is underwater

**Instagram / TikTok izohi:**

> My MacBook screen is now full of real water 💧 Tilt the lid and it flows, rock it and it splashes. Also comes in liquid mercury and lava 🌋
>
> App: Liquid Desktop — link in bio
>
> #macbook #macos #setup #desksetup #techtok #apple #macbookpro #productivity #satisfying #coding

**X (Twitter):**

> I built a Mac app that fills your screen with real water physics.
>
> Tilt the MacBook lid → the water flows. Rock it → it splashes. Your desktop bends through it like glass.
>
> $2.99, no subscription. [link]

**Reddit** (r/macapps — o‘z qoidalariga ko‘ra "self-promo" yorlig‘i bilan):

> [Release] Liquid Desktop — real-time water physics over your desktop that follows your MacBook's lid angle. One-time $2.99. Built natively (Swift + Metal), nothing leaves your Mac. Happy to answer questions about how the fluid sim works.

## 3. Sotuvni ulash (Lemon Squeezy — tavsiya)

Lemon Squeezy soliq/VAT’ni o‘zi hal qiladi va DMG yetkazib berishni o‘z zimmasiga oladi. Ro‘yxatdan o‘tishdan oldin **pulni O‘zbekistonga (yoki sizning bank/karta mamlakatingizga) chiqarish mumkinligini** tekshiring — bo‘lmasa Gumroad yoki Paddle’ni ko‘ring.

1. lemonsqueezy.com → Store yarating → **New product**: "Liquid Desktop", $2.99, *Single payment*.
2. **Files**: `Liquid Desktop.dmg` ni yuklang (xariddan keyin avtomatik yuboriladi).
3. Product → **Share** → checkout havolasini nusxalang.
4. `site/index.html` oxiridagi qatorlarga qo‘ying:
   ```js
   const CHECKOUT_URL = "https://…lemonsqueezy.com/buy/…";
   const SUPPORT_EMAIL = "siz@…";
   ```

## 4. Saytni joylash

Eng tezi — **Netlify Drop** yoki **Cloudflare Pages**: `site/` papkasini sudrab tashlaysiz, bepul HTTPS manzil olasiz. Keyin domen ulasangiz bo‘ladi (masalan `liquiddesktop.app` — bo‘sh-bo‘shligini tekshiring).

## 5. Gatekeeper (majburiy)

Hozirgi DMG faqat mahalliy sertifikat bilan imzolangan — boshqa Mac’da "app is damaged / can't be opened" xatosi chiqadi va sotuvni o‘ldiradi. Sotishdan oldin:

1. Apple Developer Program ($99/yil).
2. `make notarize CODESIGN_IDENTITY="Developer ID Application: Ism (TEAMID)"`

## 6. Natijani o‘lchash (1–2 hafta)

| Ko‘rsatkich | Davom etish | To‘xtatib, keyingi g‘oyaga o‘tish |
|---|---|---|
| Video ko‘rishlar | 10 000+ | < 2 000 |
| Saytga o‘tish (ko‘rishdan) | 2–3%+ | < 0.5% |
| Xaridlar | 50+ | < 10 |

Lemon Squeezy dashboard’i xaridlar va checkout ochilishlarini ko‘rsatadi. Saytga analitika qo‘shmoqchi bo‘lsangiz, privacy sahifasidagi "no analytics" jumlasini ham yangilang.
