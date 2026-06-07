/* =======================================================================
   88-DAY CALENDAR — CONTENT FILE
   This is the ONLY file you edit to add content. The engine (calendar.html)
   never needs to change.

   • Add a day whenever you want, in any order.
   • Any day you leave out shows a gentle "coming soon" placeholder, so the
     calendar always works even when it's half finished.

   Schema for each day — every field is optional (but give it a `reason`):
     category : "music" | "youtube" | "photo" | "quote" | "joke" |
                "inside" | "question" | "coupon" | "note" | "finale"
                -> only drives the emoji / accent / little label
     reason   : the cocky one-liner headline ("Reason #N you'll fall for me…")
     body     : short text. HTML allowed (e.g. <b>bold</b>); \n = line break
     spotify  : a Spotify link (track / album / playlist) -> embedded player
     youtube  : a YouTube link or id                      -> embedded video
     image    : an image URL or local path (e.g. "img/day5.jpg")
     ask      : true -> shows a reply box; her answer is sent to your Telegram

   You can combine `body` + ONE media (spotify OR youtube OR image).
   ======================================================================= */

window.CAL_ENTRIES = {

  1: {
    category: "note",
    reason: "Reason #1 you'll fall for me: I actually show up",
    body: "Day one without you already, bro 🥲\nI made you 88 of these — one a day. No pressure, open them whenever you miss me 😏"
  },

  2: {
    category: "music",
    reason: "Reason #2: my music taste is immaculate",
    body: "On repeat since I left. Reminded me of you.",
    spotify: "https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b"
  },

  3: {
    category: "joke",
    reason: "Reason #3: I'm objectively hilarious",
    body: "Why did the Aussie sun break up with the moon?\n\n…it needed some <b>space</b> 🌚 (like someone I know 👀)"
  },

  5: {
    category: "photo",
    reason: "Reason #4: look at the life you're missing 🌏",
    body: "Today's office. Not bad, eh?",
    image: "img/day5.jpg"
  },

  7: {
    category: "question",
    reason: "Reason #5: I actually listen",
    body: "Real question, no joke this time — what's one thing you keep putting off that you secretly really want to do?",
    ask: true
  },

  10: {
    category: "coupon",
    reason: "Reason #6: I've already got plans for us",
    body: "🎟️ <b>ONE GUILT-FREE DATE</b><br>Redeemable the day I land. No expiry. I'm paying."
  },

  88: {
    category: "finale",
    reason: "Day 88. So… did you miss me? 😏",
    body: "88 days ago you weren't sure.\nIf you're reading this, you made it all the way here — with me.\nSame question as day one: <b>did you miss me?</b>\nLet's find out over that date. 💍"
  }

  /* add more like:
  4:  { category:"inside", reason:"Reason #X: brooo we just get each other", body:"…" },
  6:  { category:"youtube", reason:"Reason #X: watch this with me", youtube:"https://youtu.be/xxxxxxxxxxx" },
  9:  { category:"quote", reason:"Reason #X: I'm kinda deep sometimes", body:"\"…\"" },
  */

};
