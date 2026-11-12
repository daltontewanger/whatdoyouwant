# What Do You Want?!

**Decide where to eat together, without the back-and-forth.**

What Do You Want?! turns "I don't know, what do you want?" into a two-minute group decision.
One person starts a room, everyone joins on their own phone, and the group swipes through the
same nearby restaurants until a winner falls out. Breakfast, lunch, dinner or whenever.

Try it at **[getwhatdoyouwant.app](https://getwhatdoyouwant.app)**.

## What it does today

- **Group rooms.** A host sets the search (distance, how many spots, cuisines to prefer or
  leave out, open now) and the app builds one shared set of nearby restaurants for the room.
- **Easy joining.** Friends join with a room code, a link or a QR code, as guests. No account
  or download needed to join: it runs in the browser. Nicknames show who's in the room.
- **Everyone gets a say.** Each person swipes right for yes and left for no, or taps the
  thumbs-up and thumbs-down buttons instead. Cards that time out count as a no, and anyone who
  needs more time can turn the timer off for the whole room.
- **Results.** The winning spot, why it won, a backup plan, and links for the map,
  directions, website and phone.
- **Tell Me What I Want.** A quick solo pick, with rerolls from the same set.
- **We'll Decide What We Want.** Vote on your own list of usual spots, with no restaurant
  search at all.
- **Favorites and Never What I Want.** Save spots you love and keep out the ones you don't.
- **Report a place** that has closed or shows a wrong website, phone number or map spot.
- **Try the demo** without signing up; it runs entirely on your device.
- **Accounts for hosts.** Starting a search needs a verified account, with email and password
  or Google sign-in. Accounts can be deleted from the app at any time, along with their data.
- **Fair use, built in.** Restaurant searches come from a paid provider, so each account gets a
  weekly allowance, with a server-side spending stop behind it. No ads and no payments.
- **Privacy first.** Your location is used only to find restaurants near you; your exact
  location is never stored or sent to analytics. Usage counts are anonymous daily totals
  and can be turned off. The site and app load nothing from third-party font or ad services.
- **Accessible.** Voting works without swiping or a timer, controls are labelled for screen
  readers, text follows your device size, and the site's
  [accessibility statement](https://getwhatdoyouwant.app/accessibility) lists what's left to
  improve.

## What's coming

- **iOS and Android apps** in the App Store and Google Play.
- **New artwork and continued design work** across the app and site.

## How it's built

- **App:** Flutter, shipped as a web app at `/app` (Android and iOS builds to follow).
- **Backend:** Firebase: Authentication, Cloud Firestore with locked-down security rules,
  App Check, and Cloud Functions for every room action. Clients write only their own votes,
  and the rules check each one.
- **Restaurant data:** HERE, behind a provider layer on the server. Each decision gets one
  stored set of restaurants that every person in the room reuses.
- **Website:** static HTML, CSS and JavaScript in `site/`, served by Firebase Hosting alongside
  the app.

Environments are kept apart: local emulators for development, a staging project for
pre-release checks, and production. Deploys are manual and reviewed; see the scripts in
`scripts/` and the commands in `AGENTS.md`.

## Help and legal

- [Support](https://getwhatdoyouwant.app/support)
- [Privacy policy](https://getwhatdoyouwant.app/privacy)
- [Terms of use](https://getwhatdoyouwant.app/terms)
- [Cookie policy](https://getwhatdoyouwant.app/cookies)
- [Delete your account](https://getwhatdoyouwant.app/delete-account)

Restaurant data © HERE.
