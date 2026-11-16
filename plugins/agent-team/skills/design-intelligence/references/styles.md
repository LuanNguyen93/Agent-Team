# Style directions

Pick one and commit. This is a menu, not a checklist.

## Bespoke Domain-Driven Art Direction Archetypes

For production surfaces and interactive prototypes (`docs/prototype.html`), select one of the **5 Supreme Art Direction Archetypes** (full token recipes & composition laws in `references/art-direction-and-composition.md`):

| Archetype (`--archetype`) | Masters & Exemplars | Reads as | Best-Fit Domains | Signature Rules |
|---|---|---|---|---|
| `swiss-editorial` | Josef Müller-Brockmann, Vignelli, Kinfolk, Stripe Press | Authored, architectural, intellectual | Knowledge tools, research, publishing, AI synthesis, executive briefings | Paper `#FAF8F5`, exposed `1px` hairlines (`#DFDCD4`), Display Serif + Grotesque + Tabular Mono, `0–4px` crisp corners |
| `monolithic-precision` | Linear, Raycast, Vercel, Quant Cockpits | Ultra-fast, obsidian, high-craft | DevTools, observability, quant finance, infrastructure control planes | Carbon `#0B0D10`, elevated graphite `#13161C`, top `1px` specular rim, tight `6–8px` radii, keyboard-first density |
| `rams-industrial` | Dieter Rams (Braun), Teenage Engineering, Leica | Tactile, honest, physical instrument | Audio/video studios, hardware companions, CAD/scientific tools, workflow engines | Anodized stone `#F2EFE9`, matte graphite `#1E1E1C`, Braun International Orange `#EA580C` signal, recessed wells |
| `shibui-organic` | Kenya Hara (MUJI), Kengo Kuma, Aesop | Calm, sunlit, biophilic, human | Health & longevity, mindful productivity, climate/biotech, consumer wellness | Sunlit linen `#FAF7F2`, espresso ink `#1C1917`, sage `#0D9488`, generous *Ma* negative space, `14–18px` concentric radii |
| `kinetic-atelier` | Rauno Freiberg, Apple Design Awards, Craft Interactive | Monumental, gallery-grade, choreographed | Creative suites, flagship launches, design engineering portfolios | Gallery canvas `#F7F6F2`, `56px–88px` display scale, staggered spring cascades (`calc(var(--i) * 35ms)`), `8:4` asymmetric stage |

## Classic UI Style Catalogue

| Direction | Reads as | Fits | Avoid when |
|---|---|---|---|
| **Flat / functional** | Neutral, fast, trustworthy | Dashboards, admin, B2B tools | Consumer product needing personality |
| **Soft / rounded** | Approachable, friendly | Consumer apps, onboarding, health | Dense data, financial gravity |
| **Editorial** | Considered, authored | Docs, blogs, marketing, long-form | Dense interactive UI |
| **Brutalist** | Raw, confident, opinionated | Dev tools, portfolios, indie products | Enterprise buyers |
| **Glassmorphism** | Layered, modern, atmospheric | Media-rich overlays, hero sections | Text-dense screens - contrast suffers |
| **Neumorphism** | Tactile, quiet | Niche control-panel aesthetics | Almost always - a11y contrast is poor |
| **Bento grid** | Organised, scannable, modular | Landing pages, feature summaries | Linear reading flows |
| **Dense / terminal** | Expert, efficient | Monitoring, logs, trading, power tools | Casual or first-time users |

## Choosing

Ask who the user is and how often they will see this screen.

- **Used all day by an expert** - density beats delight (`monolithic-precision` or `rams-industrial`).
- **Seen once by a stranger** - clarity and warmth (`shibui-organic` or `swiss-editorial`).
- **Read, not operated** - `swiss-editorial`.
- **Watched for anomalies** - `monolithic-precision`, with colour reserved for state.

## Committing to one

Consistency is what makes any of these work. Once chosen, it decides:

- corner radius (sharp `2px` / functional `8px` / organic `16px` + concentric inner radius)
- physical light & shadow (none / top `1px` specular rim + dual-layer ambient shadow)
- border & de-boxification (70% border-deletion rule; `1px` top hairline ledgers vs full boxes)
- composition (12-column `7:5` or `8:4` asymmetric focal split — never equal 3-card soup)
- type personality (tri-voice pairing: Display Serif/Sans + Reading Grotesque + Tabular Mono)

Write these into `docs/tokens.json` and pass `--archetype` when generating `docs/prototype.html` so components cannot drift.
