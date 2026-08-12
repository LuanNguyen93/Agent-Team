# Style directions

Pick one and commit. This is a menu, not a checklist.

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

- **Used all day by an expert** - density beats delight. Flat or dense.
- **Seen once by a stranger** - clarity and warmth. Soft or editorial.
- **Read, not operated** - editorial.
- **Watched for anomalies** - flat, with colour reserved for state.

## Committing to one

Consistency is what makes any of these work. Once chosen, it decides:

- corner radius (sharp / subtle / pill)
- shadow (none / flat / layered)
- border (hairline / heavy / absent)
- density (spacing scale multiplier)
- type personality (grotesque / humanist / serif / mono)

Write these into the token file so components cannot drift.
