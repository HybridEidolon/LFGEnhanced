# Changelog

## 0.6

- Fixed a Lua error when using the LFG tool to search for listings without
  an active listing.

## 0.5

- When a player requests an invite or is suggested for invitation by your party,
  their level, class, and roles will immediately be shown in your primary chat
  window. This is faster than waiting for the tooltip to load on the popup
  window that is shown by the Blizzard UI.
- The search results messages will now only be shown if you are actively looking
  for a Dungeon or Heroic.

## 0.4

- Fixed several bugs around the use of MemberCounts. Should generally work in
  all cases now.

## 0.3

- Fix deadline reset when searching

## 0.2

- Split LFG/LFM messages between solo and party leader entries.
- Display candidate roles by what your party needs, assuming it's a typical 5-man
  configuration.
- Search interval decreased to 30 seconds.

## 0.1

- Added basic auto-search functionality. This only auto-searches when you list
  yourself for activities which the API reports as using "Dungeon Role
  Expectations."
