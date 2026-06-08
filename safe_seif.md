# How app stores deal with vibe-coded apps

Stores don't have an "AI-coded app" detector or category. They review the **output**, not the process. But vibe-coded apps fail at predictable rates because of *how* they tend to be built, not because anyone flagged them as AI-made.

## The short answer

If your app meets policy + quality bars, no one cares whether you typed every line or had an LLM write half of it. If it doesn't, the rejection reason cites the specific failure (permissions, privacy, crashes, metadata) — never "you used AI."

## Where vibe-coded apps typically fall over

| Failure pattern | Why it's specifically a vibe-coding issue |
|---|---|
| **Over-declared permissions** | AI agents declare everything defensively. App requests `ACCESS_BACKGROUND_LOCATION` + camera + contacts but uses none of them. Google's automated scan and Apple's reviewers ask "why" — the dev can't explain. Rejection. |
| **Privacy policy mismatch** | LLM-generated policy says "we collect X, Y, Z" but the app actually collects only X. Apple specifically cross-checks. Rejection. |
| **API keys committed to public repos** | Google Play scans for known secret patterns. Apple does too. Vibe-coded projects on GitHub often leak Maps keys, Firebase configs, etc. |
| **Identical-template spam** | Stores detect when 50 apps share the same scaffolding. Mass-generated apps get culled in waves — Apple removed ~150k apps in early 2025 for being "minimum-effort." |
| **Crashes on edge cases** | LLM happy-path code looks good in screenshots but crashes when GPS denied / network offline / config missing. Apple's review devices specifically probe edge cases. |
| **No support email or one that bounces** | Boilerplate developer info → support contact fails → store auto-removes after 2-3 unanswered policy mails. |
| **Can't ship updates** | Vulnerability discovered → store gives 30 days to patch → dev doesn't understand the codebase well enough to fix → app removed. This kills more vibe-coded apps than rejection at submission ever does. |
| **Plagiarized assets** | LLMs (and stock-image search habits) pull icons/sounds with unclear licensing. Stores cross-check with reverse image search now. |

## Apple vs Google in practice

**Apple** — human review, 1–7 days, ~30% first-time rejection rate. They care about:
- Originality and UX quality. They explicitly reject "minimum-functionality apps" under guideline 4.2 — a vibe-coded calculator with no unique angle gets rejected even if it works perfectly.
- Apple Intelligence / Foundation Models declaration if you use on-device LLM features.
- Multi-step privacy disclosures including third-party SDK behavior.

**Google** — mostly automated review, hours to days, easier to get on initially. They care about:
- Policy compliance (background location form, foreground service types, prominent disclosure of data sharing).
- Post-publication health: crash rate, ANR rate, user reviews. Apps with > 1.8% crash rate get flagged.
- Aggressive removal of "low-quality apps" — they ran a 2024 sweep that removed 2.3M apps for "limited functionality" and "high background battery drain."

Net: **easier to get on Google, easier to get kicked off Google.** Apple's wall is higher upfront but more stable once you're through.

## The real distinction

It's not "AI-coded vs. human-coded" — that's a useless dichotomy in 2026. The line stores actually enforce is:

| ✅ Survives | ❌ Fails |
|---|---|
| You used AI to scaffold/help; you can read the code, debug edge cases, prune permissions, write accurate privacy text, and ship a patch within 48 hours of a policy mail | You used AI to generate; you can't explain what permission X is for; you can't reproduce a crash; you can't ship an update because the codebase is a black box to you |

Wakey is firmly in the first column. You've debugged a Kotlin cross-drive issue, fixed a stationary-GPS bug, swapped Google Maps for OSM after understanding the tradeoff, and you can answer for every permission you've declared. That's *AI-assisted development*, which is just modern development. Stores don't penalize that.

## Recent trends (2025–2026)

- Neither store has a specific "AI-generated app" policy. Both have specific "AI-generated **content**" disclosure rules (image gens, chatbots) — different thing.
- Google added "spam app" detection in late 2025 — pattern-matches against known template-app generators. Apps that come out of "no-code AI app builder" platforms get auto-flagged for extra review.
- Apple started rejecting apps where the demo video shown in App Store screenshots doesn't match actual behavior — kills LLM-generated marketing material that overpromises.
- Both stores increased scrutiny on first-time developers signing up in 2025. Expect ID verification, payment-method checks, and a higher rejection rate on your first submission regardless of how the code was written.

## Bottom line

The stores' problem isn't with AI in the dev loop — it's with developers who can't maintain what they ship. If you can read your own code, debug it, prune the unnecessary parts, and ship updates, your app is treated exactly like a hand-written one. The fact that this conversation involved you understanding *why* `kotlin.incremental=false` mattered, *why* the stationary-GPS bug fired only after a minute — that's the signal that you're on the safe side of the line.
