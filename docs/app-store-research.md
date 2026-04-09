# Apple App Store Research for ShareSesh

## TL;DR

- **The $99/year Apple Developer Program fee is unavoidable** for selling a native app on the App Store. There is no legitimate bypass for individuals.
- **Fee waivers exist** only for nonprofits (501(c)(3)), accredited educational institutions, and government entities.
- **Best free alternative**: Build a Progressive Web App (PWA) -- no fee, no Apple commission, but limited iOS capabilities.
- **Commission**: Apple takes 30% of sales, or **15% if you earn under $1M/year** (Small Business Program).

---

## Can You Bypass the $99/Year Fee?

### No free path to the App Store for individuals

| Method | Cost | Can You Sell an App? |
|--------|------|---------------------|
| App Store (standard) | $99/year + 30% commission | Yes |
| App Store (Small Business) | $99/year + 15% commission | Yes (if < $1M revenue) |
| Free Apple Developer account | $0 | **No** -- personal device testing only, 7-day cert expiry |
| PWA (Progressive Web App) | $0 | Yes (via your own payment system, 0% Apple commission) |
| Web app | $0 | Yes (via your own payment system) |
| TestFlight | $99/year | **No** -- beta testing only, 90-day expiry, no monetization |
| Alt marketplace (EU only) | $99/year + possible fees | Yes, but EU users only |
| Enterprise Program | $299/year | **No** -- internal company apps only |

### Fee waiver eligibility (organizations only)

- **501(c)(3) nonprofits** -- fee waived
- **Accredited educational institutions** -- fee waived
- **Government entities** -- fee waived
- Open-source projects alone do **not** qualify

---

## Apple's Commission Structure

| Scenario | Apple's Cut |
|----------|-------------|
| Paid app download | 30% |
| In-app purchases | 30% |
| Auto-renewable subscriptions (year 1) | 30% |
| Auto-renewable subscriptions (year 2+) | 15% |
| **Small Business Program** (< $1M/year revenue) | **15%** |
| Free app, no IAP | 0% |

### Small Business Program

- Reduces commission from 30% to **15%** on all paid apps, IAP, and subscriptions
- Eligible if your total App Store earnings are **$1M or less** in the prior calendar year
- Must apply through Apple's developer portal (not automatic)
- If you cross $1M mid-year, 30% rate kicks in for the rest of that year

---

## How to Sign Up (Individual)

1. **Create an Apple ID** at appleid.apple.com (if you don't have one)
2. **Enable two-factor authentication** on the Apple ID
3. **Download the Apple Developer app** on an iPhone or iPad
4. **Go to** [developer.apple.com/programs](https://developer.apple.com/programs/) and click "Enroll"
5. **Select "Individual"** enrollment type
6. **Provide**: legal name, address, phone number
7. **Verify identity**: scan government-issued photo ID via the Apple Developer app
8. **Pay $99** annual fee
9. **Wait 24-48 hours** for approval (can take longer if extra verification needed)

### Requirements

- Must be 18+ years old
- Government-issued photo ID (passport or driver's license)
- iPhone or iPad (for identity verification via Apple Developer app)
- Valid credit/debit card for the $99 fee

### For Organizations (companies, nonprofits)

Additional requirements:
- **D-U-N-S number** (free from Dun & Bradstreet, but takes up to 30 business days to obtain)
- Company email address (not Gmail/Yahoo)
- Legal authority to bind the organization
- Approval takes **1-4 weeks**

---

## Alternatives to the App Store

### 1. Progressive Web App (PWA) -- Best Free Option

- **Cost**: $0 (no Apple developer account needed)
- **Commission**: 0% (use your own payment processor like Stripe)
- **Capabilities on iOS**: offline support, home screen install, push notifications (iOS 16.4+), camera, microphone, geolocation
- **Limitations on iOS**: no Bluetooth, limited background execution, no NFC/HealthKit, no App Store discoverability, storage can be purged by OS
- **Good for**: content apps, social apps, e-commerce, media, utilities

### 2. Web App

- Standard mobile-optimized website
- No review process, no commission, instant updates
- Most limited native capabilities

### 3. EU Alternative Marketplaces (EU Users Only)

- Since iOS 17.4 (March 2024), third-party app stores exist in the EU (AltStore PAL, Setapp Mobile, Epic Games Store)
- Still requires $99/year Apple Developer Program membership
- Subject to Apple's Core Technology Fee: EUR 0.50 per first annual install over 1M installs
- Apps go through Apple's notarization (lighter than full App Store review)

### 4. TestFlight (Not for Sales)

- Requires $99/year membership
- Up to 10,000 external testers
- Apps expire after 90 days
- Cannot charge users -- testing only

---

## Recommendation for ShareSesh

If the goal is to **sell ShareSesh as an iOS app**:

1. **Pay the $99/year** -- it's the only path to the App Store for individuals. There is no workaround.
2. **Apply for the Small Business Program** immediately after enrollment to get the **15% commission rate** instead of 30%.
3. **Consider starting with a PWA** if $99/year is a barrier -- you can accept payments directly (Stripe, etc.) with 0% Apple commission, and convert to a native app later.

### Quick Cost Comparison for a $4.99 App

| Distribution | Your Revenue per Sale |
|-------------|----------------------|
| App Store (30% commission) | $3.49 |
| App Store (Small Business, 15%) | $4.24 |
| PWA with Stripe (~2.9% + $0.30) | $4.55 |

---

## Important Note

I (Claude) **cannot sign up for the Apple Developer Program on your behalf**. Enrollment requires:
- Your personal identity verification (photo ID scan)
- Your Apple ID credentials
- Your payment information

You must complete enrollment yourself at [developer.apple.com/programs](https://developer.apple.com/programs/).
