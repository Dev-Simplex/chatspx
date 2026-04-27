# WhatsApp Web/Desktop Design System Reverse-Engineered Specification

> **Scope:** This document reconstructs the visual, interaction, and component system implied by the provided WhatsApp web/login/loading/desktop screens. It is written as a production-ready foundation for product design, engineering implementation, and Figma systemization.

---

## 1. Product Overview

### Purpose of the app
WhatsApp is a cross-platform communication product centered on:
- Private 1:1 messaging
- Group communication
- Voice/video calling
- Device linking and multi-device continuity
- Lightweight onboarding and desktop web access
- Privacy-first trust signaling via end-to-end encryption messaging

The provided screens focus primarily on:
- Public marketing landing page
- Desktop/web authentication and linking
- Loading and device readiness states
- WhatsApp desktop shell / inbox landing experience

### Target users (inferred)
The product serves several user groups:

| Segment | Needs |
|---|---|
| General consumers | Fast, low-friction private messaging across devices |
| Cross-device users | Link phone to web/desktop, continue conversations on larger screens |
| New users / re-auth users | Enter phone number, verify via QR or device code |
| Returning users | Resume session quickly, avoid repeated login |
| Desktop users | Use WhatsApp on macOS / browser with integrated chat management |
| Privacy-conscious users | Clear security signals and encrypted messaging assurance |

### Core use cases
- Discover WhatsApp and install/download app
- Login via QR code or phone-number based flow
- Link device from phone
- Wait while chats load / session initializes
- Browse chats and system prompts in desktop shell
- Launch secondary actions such as download app, add contact, send document, or use Meta AI

---

## 2. User Flows

## 2.1 Marketing Landing → Download
### Entry points
- Public homepage
- Direct navigation from external links
- Footer references and download CTAs

### Step-by-step journey
1. User lands on hero page.
2. Sees brand identity, headline, supporting copy.
3. Reviews hero message and brand imagery.
4. Clicks primary CTA: **Download**.
5. Potential redirect to platform-specific download or app store.

### Decision branches
- If user is on desktop and not installed, download is the default action.
- If user is on mobile, CTA may route to app store or deep link.

### Exit points
- App download page
- Platform store
- Onboarding/login flow

---

## 2.2 Desktop/Web Login via QR Code
### Entry points
- Desktop login page
- “Log in with QR code” link from phone number screen
- Auth/session expiration

### Step-by-step journey
1. User opens login page.
2. System displays login instructions and QR code panel.
3. User opens WhatsApp on phone.
4. User navigates to Linked Devices.
5. User scans QR code.
6. Desktop session authenticates.
7. Chats begin loading.

### Decision branches
- QR unavailable/loading → placeholder loader
- QR scan success → session established
- QR scan failure or timeout → refresh/retry state
- User chooses phone-number login instead

### Exit points
- Chat loading state
- Phone-number login alternative
- Session error / retry flow

---

## 2.3 Desktop/Web Login via Phone Number
### Entry points
- “Log in with phone number”
- Explicit phone-number login mode

### Step-by-step journey
1. User selects country from dropdown.
2. User enters phone number in formatted input.
3. User proceeds with **Next**.
4. System transitions to code entry / linking flow.
5. User returns to QR flow if desired.

### Decision branches
- Country selection changes calling code
- Invalid/empty number disables Next
- User can switch back to QR login

### Exit points
- Code entry screen
- Error correction
- Login alternative route

---

## 2.4 Device Linking via Phone Code
### Entry points
- After entering phone number
- Device linking fallback from QR flow

### Step-by-step journey
1. User sees alphanumeric code grouped in blocks.
2. User opens phone app instructions.
3. User enters code on phone.
4. Desktop verifies match.
5. Session is linked.
6. Chats load.

### Decision branches
- Code expires → regenerate/reset
- Code entered successfully → continue
- User chooses QR code instead → alternate auth path

### Exit points
- Loading chats
- Error/retry if mismatch or expiration

---

## 2.5 Loading Chats
### Entry points
- Successful authentication
- Initial app boot after session restore

### Step-by-step journey
1. Screen shows centered WhatsApp icon or loading mark.
2. Progress bar animates.
3. Copy confirms end-to-end encryption.
4. After load completes, desktop inbox opens.

### Decision branches
- Fast load → minimal exposure
- Slow load → loading persists
- Failure → error message or retry shown in a resilient implementation

### Exit points
- Inbox / shell
- Retry/error recovery

---

## 2.6 Inbox / Desktop Shell
### Entry points
- Successful load after authentication
- Restored session

### Step-by-step journey
1. Left rail appears with app navigation.
2. Chat list column loads.
3. Search bar and filter chips appear.
4. Alerts/cards may appear at top of chat list.
5. Main content pane shows onboarding/empty-state card or selected conversation.
6. User can begin a conversation, add contacts, send documents, or install desktop app.

### Decision branches
- No chats → empty state
- Notifications off / language mismatch → dismissible system banners
- User selects a conversation → main pane updates
- User engages CTA cards → secondary workflows launch

### Exit points
- Chat conversation
- Contacts flow
- Meta AI flow
- File send flow

---

## 3. Information Architecture

### Screen hierarchy
1. **Marketing / Home**
2. **Login**
   - QR login
   - Phone-number login
   - Code entry / device link
3. **Loading**
4. **Desktop Inbox Shell**
   - Sidebar navigation
   - Chat list
   - Main canvas / empty state / prompt cards

### Navigation structure
The product uses a **hybrid architecture**:
- **Public site**: top navigation header
- **Authentication flows**: stacked, linear screens
- **Desktop app shell**: persistent left nav rail + content split pane

### Content grouping logic
- **Primary actions** are surfaced as prominent green CTAs.
- **Trust and safety information** is separated into low-emphasis footers and banners.
- **Authentication instructions** are grouped in numbered steps.
- **System banners** appear above the chat list for device or preference issues.
- **Empty-state CTAs** are centralized in the right pane with contextual shortcuts.

---

## 4. Layout System

### Grid system
The design is based on a **centered desktop layout** with a max-width content column and generous page gutters.

| Region | Behavior |
|---|---|
| Global page | Full-bleed background with centered content |
| Hero | Large rounded container spanning most of viewport width |
| Auth cards | Centered fixed-width cards stacked vertically |
| Desktop shell | Left sidebar fixed width + right content canvas |
| Footer area | Center-aligned legal/trust text |

### Estimated columns
- Marketing page: 12-column conceptual grid with large outer margins
- Auth page: single centered column within a larger canvas
- Desktop app: 2-pane layout:
  - Left rail: narrow icon strip
  - Chat list: medium width panel
  - Main canvas: flexible remainder

### Spacing scale
This UI strongly suggests an **8px-based system**, with additional 4px increments for fine typographic spacing.

| Token | Estimate |
|---|---:|
| xs | 4px |
| sm | 8px |
| md | 12px |
| base | 16px |
| lg | 20px |
| xl | 24px |
| 2xl | 32px |
| 3xl | 40px |
| 4xl | 48px |
| 5xl | 64px |

### Safe areas and padding rules
- Pages use generous outer padding, especially on the marketing and auth flows.
- Cards maintain consistent internal padding around 24–32px.
- Hero content avoids edge contact by using large rounded containers.
- Footer text sits below primary content with distinct vertical separation.
- Desktop shell respects native window edges but retains internal inset spacing.

### Alignment patterns
- Major modules are **center aligned** on auth pages.
- Marketing hero uses **left-aligned copy** over a visual backdrop.
- Buttons and links are aligned to content baselines.
- Lists and login steps are left-aligned for readability.
- Utility controls in the desktop shell are right-aligned within header space.

---

## 5. Design Tokens (inferred)

## 5.1 Colors

### Core palette
WhatsApp’s brand is centered on green, neutral surfaces, and warm off-white backgrounds.

| Token | Approximate Use | Inferred Value |
|---|---|---|
| `color.brand.500` | Primary CTA, brand logo, progress bars | `#25D366` / similar WhatsApp green |
| `color.brand.600` | Hover/active brand states | darker green |
| `color.brand.050` | Light success surfaces / chips | pale green tint |
| `color.surface.page` | App background | warm ivory / cream |
| `color.surface.card` | Cards and panels | white |
| `color.surface.subtle` | Banners, inputs, disabled containers | off-white / light gray |
| `color.text.primary` | Main body text | near-black / charcoal |
| `color.text.secondary` | Secondary copy | medium gray |
| `color.text.muted` | Legal and footnote text | gray-brown |
| `color.text.inverse` | Text on dark imagery or green buttons | white or near-white |
| `color.border.default` | Card and control borders | dark gray / neutral |
| `color.border.focus` | Focus/active state outline | brand green |
| `color.state.success` | Success messaging | green |
| `color.state.warning` | Warning banners | warm yellow / amber |
| `color.state.error` | Error states | red |
| `color.state.info` | Informational banners | blue/neutral |

### Surface hierarchy
1. Page background: warm cream
2. Card background: white
3. Secondary panels: light gray
4. System banners: tinted surfaces
5. CTA buttons: brand green

### Functional color usage
- **Green** is overloaded for brand, action, success, and progress.
- **Yellow/amber** communicates caution.
- **Gray** communicates system/disabled/loading.
- **Black/charcoal** drives content legibility and visual confidence.

---

## 5.2 Typography

### Font families
The system appears to use a **modern sans-serif UI font**, likely:
- Primary: system sans or a rounded grotesk-style sans
- Secondary: same family with different weights

Likely characteristics:
- High x-height
- Neutral geometric construction
- Excellent screen readability
- Tight brand integration with WhatsApp’s modern web presence

### Type scale
| Token | Approx Size | Typical Use |
|---|---:|---|
| `type.xs` | 11–12px | Legal, footnotes |
| `type.sm` | 13–14px | Helper text, metadata |
| `type.md` | 15–16px | Body copy, buttons |
| `type.lg` | 18–20px | Section labels, card titles |
| `type.xl` | 24px | H2 / page headings |
| `type.2xl` | 32px | Login page headings |
| `type.3xl` | 56–64px | Hero headline |

### Weights
| Weight | Use |
|---|---|
| 400 | Body, helper text, instructional text |
| 500 | Button labels, highlighted inline text |
| 600 | Card titles, strong labels, link emphasis |
| 700 | Hero emphasis, important headings |

### Line heights
- Body text: 1.35–1.5
- Headings: 1.0–1.15
- Instructions / step lists: 1.3–1.4
- Legal text: 1.4–1.6 for compact readability

### Typography behavior
- Headings are large and emotionally direct.
- Instructions use short, readable lines.
- Links and emphasized actions often use underline or weight rather than color alone.
- Legal text is intentionally low-emphasis and small.

---

## 5.3 Spacing
The system is clearly consistent with a **4pt/8pt modular scale**:
- Primary rhythm: 8px
- Fine adjustments: 4px

### Recommended spacing tokens
`4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80`

---

## 5.4 Radius & Elevation

### Border radius scale
| Token | Estimate | Use |
|---|---:|---|
| `radius.sm` | 6px | Inputs, small chips |
| `radius.md` | 10–12px | Buttons, banner blocks |
| `radius.lg` | 16–20px | Cards, panels |
| `radius.xl` | 24–28px | Hero container, large surfaces |
| `radius.pill` | 999px | Pills, chips, CTA buttons |

### Elevation / shadow system
The product uses **very light elevation**:
- Mostly outline-based components
- Subtle shadow only where needed
- Cards rely on border + white fill rather than heavy drop shadows

| Level | Use |
|---|---|
| 0 | Flat surfaces, page background |
| 1 | Cards and panels with border |
| 2 | Floating menus / overlays |
| 3 | Modal / dialogs |

### Depth strategy
- Borders are more important than shadows.
- Rounded corners soften the interface.
- Elevated elements remain restrained to preserve WhatsApp’s calm, trustworthy tone.

---

## 6. Component System

## 6.1 Primary Button
### Purpose
Primary conversion action for download, next step, or login confirmation.

### Variants
- Default green filled
- Secondary outlined (where needed)
- Small / compact
- Icon + text
- Text-only CTA in some contexts

### Anatomy
- Container
- Label
- Optional leading/trailing icon

### Properties
- `size`: small, medium, large
- `variant`: primary, secondary, text
- `icon`: none / leading / trailing
- `width`: auto or fixed
- `disabled`: true/false

### States
- **Default:** green fill, dark text
- **Hover:** darker green or slightly raised
- **Pressed:** deeper green, reduced elevation
- **Focus:** visible outline in brand green
- **Disabled:** pale green/gray fill, muted text
- **Loading:** spinner inline or replace label

---

## 6.2 Text Link / Inline CTA
### Purpose
Secondary navigation and alternate routes.

### Variants
- Underlined link
- Arrow-link
- Inline emphasized text link

### Anatomy
- Text label
- Optional arrow icon

### States
- Default
- Hover: underline or color shift
- Pressed: active state
- Focus: keyboard ring
- Disabled: muted / no underline

### Behavioral rules
- Used for fallback paths:
  - “Log in with phone number”
  - “Log in with QR code”
  - “Get started”
- Often appears below primary CTAs to preserve hierarchy.

---

## 6.3 Card / Panel
### Purpose
Primary container for onboarding, login, and system prompts.

### Variants
- Auth card
- Banner card
- Empty-state card
- Hero content container
- Prominent CTA card

### Anatomy
- Background surface
- Border
- Optional icon area
- Title
- Description
- Action region

### States
- Default
- Hover: subtle border emphasis
- Focus within: control outline
- Loading: skeleton content / placeholder
- Error: red border or error banner inside
- Dismissible: close affordance

### Behavioral rules
- Cards are centered and highly legible.
- Inner sections follow strong vertical hierarchy.
- Cards may include embedded CTA, instruction list, or illustration.

---

## 6.4 Navigation Header
### Purpose
Global brand presence and primary site navigation.

### Anatomy
- Brand logo
- Text navigation links
- Utility actions (Log in / Download)

### Properties
- Sticky or static depending on page context
- Desktop-first presentation
- Simplified top-level hierarchy

### States
- Default
- Hover on menu item
- Active/current page indicator
- Focus for keyboard users

### Behavioral rules
- Download is the strongest top-right CTA.
- Login is secondary but still visible.
- Navigation uses a clean editorial style, not a dense app nav.

---

## 6.5 Search Field
### Purpose
Search chats or ask Meta AI / search content in the inbox.

### Anatomy
- Leading search icon
- Input area
- Placeholder text
- Optional clear control

### States
- Default
- Focus: border or background emphasis
- Filled
- Disabled
- Error
- Loading/searching

### Behavioral rules
- Appears in the left chat panel.
- Rounded pill shape.
- Minimal chrome, low visual noise.

---

## 6.6 Filter Chips / Segmented Pills
### Purpose
Quick filtering in the chat list.

### Variants
- All
- Unread
- Favourites
- Groups

### Anatomy
- Pill surface
- Text label
- Optional selected state fill

### States
- Default
- Selected
- Hover
- Pressed
- Disabled
- Focus

### Behavioral rules
- One selected state at a time or multi-select depending on implementation.
- Selected chip uses green-tinted fill.
- Unselected chips use outlined neutral styling.

---

## 6.7 Banner / Alert
### Purpose
Surface important system messages and guidance.

### Variants
- Warning banner
- Info banner
- Success/notice banner
- Dismissible system alert

### Anatomy
- Leading icon
- Headline
- Supporting text
- Inline CTA link
- Optional close icon

### States
- Default
- Hover on action/close
- Dismissed
- Expanded/collapsed if necessary

### Behavioral rules
- Full-width within chat list.
- Uses colored backgrounds to distinguish severity.
- Can be stacked vertically.
- Warning takes precedence over informational messages.

---

## 6.8 Step List / Numbered Instruction Component
### Purpose
Guide users through multi-step login/linking tasks.

### Anatomy
- Step number in circle
- Vertical connector line
- Step label text
- Inline icons in text

### Variants
- 4-step login guide
- Device-link guide
- Code-entry guide

### States
- Current step
- Complete step
- Pending step
- Error step

### Behavioral rules
- Steps are concise and action-oriented.
- Numbering supports sequential cognition.
- Inline device icons reinforce platform specificity.

---

## 6.9 QR Code Module
### Purpose
Device linking via scan-to-login.

### Anatomy
- QR image area
- Optional loading placeholder
- Branding mark overlay
- Instructional text nearby

### States
- Loading placeholder / spinner
- Rendered QR
- Expired / refresh required
- Error / unavailable

### Behavioral rules
- Large enough for comfortable scanning.
- Centered within a card.
- High contrast black-and-white code with strong legibility.
- Supports fallback to phone-number or code entry.

---

## 6.10 Phone Input Group
### Purpose
Capture country and phone number for login.

### Anatomy
- Country selector
- Country flag icon
- Calling code field
- Phone number input
- Next button

### States
- Default
- Focus on country select
- Focus on number input
- Filled
- Invalid
- Disabled
- Autocomplete active

### Behavioral rules
- Country select precedes number input.
- Prefix code is visually integrated into the field.
- Primary action remains disabled until valid input is likely achieved.
- Input is centered in the card and isolated for clarity.

---

## 6.11 Code Entry Blocks
### Purpose
Display and confirm login/linking code.

### Anatomy
- Fixed-width character cells
- Separator dash
- Supporting instructions
- Edit link to change phone number

### States
- Default
- Filled
- Active cursor
- Invalid / mismatch
- Expired / regenerate

### Behavioral rules
- Monospaced or monospaced-like alignment for clarity.
- Grouped as human-readable chunks.
- Used as an alternative to QR scanning.

---

## 6.12 Loading State
### Purpose
Communicate app initialization without anxiety.

### Anatomy
- Center icon/brand mark
- Label text
- Progress bar
- Encryption notice

### States
- Initial
- In-progress
- Nearly complete
- Timeout/error

### Behavioral rules
- Sparse composition.
- Strong centered vertical alignment.
- Minimal movement to reduce distraction.

---

## 6.13 Left Navigation Rail
### Purpose
Provide persistent access to major app sections.

### Anatomy
- Stack of icon buttons
- Active state indicator
- Spacer
- Bottom utility icons (settings/profile)

### States
- Default
- Active
- Hover
- Focus
- Disabled

### Behavioral rules
- Narrow and icon-based for space efficiency.
- Active item uses brand-colored indicator.
- Utility items live near the bottom to separate core from settings actions.

---

## 6.14 Empty State / Prompt Card
### Purpose
Guide first-time or no-chat users to actionable next steps.

### Anatomy
- Illustration
- Title
- Supporting text
- CTA button
- Shortcut tiles

### States
- Empty inbox
- No results
- New user
- Recommendation / install prompt

### Behavioral rules
- Centered in the main pane.
- Encourages immediate action rather than passive waiting.
- Supports multiple distinct entry actions.

---

## 6.15 Shortcut Tiles
### Purpose
Quick-access actions like sending a document, adding contact, asking Meta AI.

### Anatomy
- Icon
- Title/label
- Optional subtext

### States
- Default
- Hover
- Pressed
- Disabled

### Behavioral rules
- Small square tiles with low contrast backgrounds.
- Used as secondary actions beneath the main prompt card.

---

## 7. Interaction Patterns

### Gestures
- **Tap/click:** primary interaction across buttons, links, chips, and navigation icons.
- **Keyboard enter:** submit login forms and confirm actions.
- **Keyboard navigation:** expected for forms and desktop shell.
- **Dismiss click/tap:** close banners.

### Feedback
- Buttons likely use subtle press compression and color darkening.
- Loading bars animate linearly and minimally.
- QR screen may animate the placeholder spinner during code fetch.
- Active nav items use persistent color state rather than motion alone.

### Transitions between screens
- Login flow transitions are mostly linear and card-based.
- QR to loading transition is immediate after success.
- Loading to inbox is a full-screen swap with minimal decorative motion.
- Page transitions preserve continuity of centered alignment and brand tone.

### Microinteractions
- Dropdown arrow rotates or shifts on open.
- Inputs highlight with green focus states.
- Chips toggle fill and border treatment.
- Dismissible banners fade or collapse on close.
- Search field likely expands or changes background on focus.

---

## 8. State Handling

## 8.1 Empty States
### Patterns
- “No chats” blank state in chat list area
- Marketing page without downstream interaction
- Empty inbox prompting install/add contact actions

### Rules
- Keep empty states constructive.
- Provide a next action, not just a message.
- Use illustrations or iconography sparingly.

---

## 8.2 Loading States
### Patterns
- QR code placeholder spinner
- Loading chats indicator with progress bar
- Potential skeletons for chat list and content pane

### Rules
- Center loading content where possible.
- Use brand green progress accents.
- Avoid busy spinners unless necessary.
- If load is indeterminate, pair with text to reduce uncertainty.

---

## 8.3 Error States
### Inferred use cases
- Invalid phone number
- Expired QR code
- Code mismatch
- Connection failure
- Session issue
- Device not synced

### Rules
- Use banner or inline message near the relevant control.
- Preserve user-entered data unless destructive reset is required.
- Offer retry or alternate route.

---

## 8.4 Success States
### Patterns
- Green CTA affirmation
- Successful linking with transition into loading
- Confirmation implied by moving to next stage

### Rules
- Avoid heavy celebratory UI; maintain trust and efficiency.
- Success is often implicit through progression.

---

## 8.5 Skeletons
### Inference
Skeleton loading is likely used in the chat list and content pane to prevent layout shift, especially when sessions restore.

### Rules
- Reflect final layout structure.
- Use neutral gray placeholders with rounded geometry.

---

## 9. Content & Copy Patterns

### Tone of voice
- Clear
- Calm
- Friendly
- Trustworthy
- Minimal jargon
- Action-oriented

### CTA patterns
- Verb-first CTAs: **Download**, **Next**, **Get started**
- Alternate action phrasing: **Log in with QR code**, **Log in with phone number**
- Supportive prompts: **Turn on**, **Update now**
- Utility actions often include arrows or small icons

### Labeling conventions
- Short section headings
- Consistent device references
- Explicit platform names: iPhone, Android, Mac
- Phone actions are described in plain language
- Legal notes remain concise and unobtrusive

### Content hierarchy rules
1. Headline
2. Supporting explanation
3. Primary CTA
4. Secondary/alternate action
5. Legal/trust text

---

## 10. Accessibility (inferred)

### Contrast considerations
- Green on cream/white should be monitored for contrast, especially in small text or thin strokes.
- Gray helper text must remain readable against warm backgrounds.
- The hero image overlays require careful text contrast management.

### Touch target sizes
- Minimum 44x44px for buttons, nav icons, chips, and close icons.
- Small icon buttons should include padding, not just icon bounds.

### Typography readability
- Body text sizes should stay at 14–16px minimum on desktop.
- Legal text should not fall below readable thresholds.
- Instruction steps need sufficient line spacing.

### Accessibility risks
- Green text links on cream backgrounds may underperform contrast standards in smaller sizes.
- Tiny footer/legal text could be missed or unreadable.
- QR and icon-heavy flows need alternate non-visual routes.
- Icon-only navigation requires accessible labels.
- Chips and step selectors need ARIA/semantic states.

### Recommended accessibility patterns
- Visible focus rings on all interactive elements
- Semantic headings and landmarks
- Keyboard-operable dropdown, search, chips, and dialogs
- Screen-reader labels for QR, country select, and code entry
- Status announcements for loading and success transitions

---

## 11. Platform Conventions

### iOS / Android patterns being used
- Country selection and phone-based login reflect mobile-native device linking.
- Menu/settings references differentiate Android and iPhone instructions.
- The overall experience is desktop-optimized but assumes a mobile companion device.
- Rounded cards, pill buttons, and sparse layouts align with modern cross-platform web conventions.

### Desktop/web conventions
- Multi-pane shell
- Persistent sidebar navigation
- Search-first discovery
- Cards and banners in content area
- Inline utility actions near the top-right

### Deviations from native behavior
- Desktop shell borrows app-like affordances but is web-based.
- Login flow is intentionally simplified and guided, more like a web onboarding wizard than a native settings screen.
- Brand styling dominates over platform-native form density.

---

## 12. Insights & System Rules

### Design principles behind the system
1. **Clarity over complexity**  
   Each screen contains one dominant task.
2. **Trust through restraint**  
   Minimal chrome, soft borders, low-motion feedback.
3. **Cross-device continuity**  
   The system is built around linking phone and desktop as one identity.
4. **Action-first composition**  
   Primary CTA is always visible and unambiguous.
5. **Privacy as a core visual motif**  
   End-to-end encryption is surfaced regularly as reassurance.
6. **Friendly utility**  
   The interface feels approachable without becoming playful or noisy.

### Consistency rules
- Green is reserved for brand, positive action, or progress.
- Rounded shapes dominate all touchpoints.
- Cards use bordered containers rather than heavy shadows.
- Typography is sparse and hierarchical.
- Alternate paths are always available beneath the primary path.
- System notices remain visually distinct from user tasks.

### Reusable patterns
- Centered login card
- Top brand header
- Green pill CTA
- Banner with inline action
- Step-based instruction list
- Rounded pill filters
- Empty state with action tiles
- Left nav rail for desktop shell

### Anti-patterns
- Overuse of green in non-action contexts
- Dense text blocks without hierarchy
- Excessive motion or flashy transitions
- Strong shadowing that breaks the calm brand tone
- Ambiguous CTAs that compete with primary actions
- Inline help that is too verbose for authentication screens

---

# Appendix: Suggested Figma / Engineering Token Model

## Core token naming
- `color.brand.primary`
- `color.brand.primaryHover`
- `color.surface.page`
- `color.surface.card`
- `color.surface.subtle`
- `color.text.primary`
- `color.text.secondary`
- `color.border.default`
- `radius.card`
- `radius.pill`
- `space.1` through `space.12`
- `type.body.md`
- `type.heading.lg`
- `shadow.elevation.1`

## Component library modules
- `Button`
- `Link`
- `Card`
- `Banner`
- `Input`
- `Select`
- `Chip`
- `StepList`
- `QRCodePanel`
- `LoadingState`
- `NavigationRail`
- `TopNav`
- `EmptyState`
- `ShortcutTile`

---

# Summary

This UI system is a **privacy-first, low-friction, highly guided cross-device communication design language** built around:
- Warm neutral backgrounds
- WhatsApp green as the singular action color
- Centered authentication cards
- Sparse but strong information hierarchy
- Lightweight bordered surfaces
- Clear fallback paths for login and device linking
- A calm, utility-driven desktop shell

It is highly suitable for rebuilding as:
- A Figma design system
- A React/Vue component library
- A responsive web app shell
- A cross-platform onboarding and authentication flow

If you want, I can next convert this into:
1. a **Figma token sheet**,  
2. a **component inventory/spec table**, or  
3. a **React component architecture + props API**.