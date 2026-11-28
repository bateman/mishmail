# Changelog

All notable changes to DreaMail (called MishMail until November 2026) are
documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); the project is pre-1.0, so
minor versions may still change behavior.

## [Unreleased]

- **Print a message, and the message menu in Gmail's groups.** The "⋮"
  menu of an open message is grouped like Gmail's, with Gmail's wording
  ("Reply all", "Delete", "Mark as unread"). The new "Print" prints that
  message (header and body) through the macOS print panel, with the
  subject as the document name; blocked remote images stay blocked. The
  app now has the sandbox print entitlement. (#129)

- **CI: UI tests use fewer macOS runner minutes.** UI-test waits return at
  once when the element is already there, UI jobs restore the unit-test
  job's build cache (read-only), and the suite runs in two balanced shards
  instead of three: about 30 runner minutes per UI run instead of about 40,
  with the same wall-clock time. The UI-test target is now built with
  warnings as errors. (#128)

- **The label colour sheet is Gmail's.** It shows Gmail's colour grid and
  "Remove color", nothing else. Mac-only label colours are gone: a label
  that had one shows its Gmail colour again (the stored value is kept but
  no longer used). (#127)

- **Menus show their icons; one search field beside the view title.** The
  right-click menu of a conversation and the "⋮" menu of an open message
  now draw an icon next to every item. The top-bar search field is a
  single rounded field (no second border around it) and stays right after
  the view title whether or not a conversation is open; the results panel
  opens under it. The collapsed sidebar no longer shows a search icon
  (`/` still focuses the field). (#126)

- **New OpenPGP library releases are integrated by a manual workflow.**
  *Integrate dreamail-openpgp* (Actions, run by hand) moves the app to the
  newest release of the library, or to the one given, and refuses
  downgrades. It first needs the whole CI, UI tests included, green on
  `main`. It then checks the release:
  - the checksum in the library's `Package.swift`, the release's `.sha256`
    and the downloaded zip agree;
  - the zip's build provenance attestation was signed by the library's
    Release workflow on its `main`, from the release's tag commit.

  It updates `project.yml`, `docs/DEPENDENCIES.md` and this file, and runs
  the whole CI again with only the pin changed. If CI is green, the pull
  request is merged. If it is red, it stays a draft. It always waits for a
  person when the library's packaging, build or release pipeline changed,
  or when its accepted advisories did. On the library's side, new rPGP
  releases are now picked up every week (once they are 7 days old),
  tested, released and attested by its own workflows.
- **The app is now DreaMail.** The fork formerly called MishMail has a new
  name and new identifiers: `/Applications/DreaMail.app`, bundle identifier
  `io.github.bateman.DreaMail` (Debug: `io.github.bateman.DreaMail.debug`),
  `dreamail://` links, `DREAMAIL_…` build switches and environment
  variables, and "Ask AI" for the assistant (still off by default). macOS
  treats it as a new app, and nothing is migrated. If you used a MishMail
  build of this fork: install DreaMail (`make install`), paste your Google
  client ID and secret again, sign in to each account and let it resync;
  set the default mail app, notifications and signatures again; rename the
  `MISHMAIL_…` switches in `Config/Local.xcconfig` to `DREAMAIL_…`. The old
  data stays until you delete it by hand: the app at
  `/Applications/MishMail.app`, the containers
  `~/Library/Containers/io.github.bateman.MishMail` and
  `~/Library/Containers/io.github.bateman.MishMail.debug`, the log
  `~/Library/Logs/MishMailRelauncher.log` (and, if you used them,
  `/tmp/mishmail-summarize.log`, `.err` and `~/.config/mishmail`), and the
  Keychain items of the
  services `io.github.bateman.MishMail`, `io.github.bateman.MishMail.debug`
  and their `.openpgp` variants (commands in the README, "Coming from a
  MishMail install of this fork"). The old Google refresh tokens are not
  revoked: they stay valid until they expire or you remove the app at
  myaccount.google.com/permissions. The About panel no longer has a "Support"
  link; it credits MishMail by Ron Boger, which DreaMail is derived from.
  Nothing changes in Google Cloud Console. The OpenPGP library moves to
  v0.2.0, which only renames it (`DreaMailRPGP`); its behaviour is that of
  v0.1.1.

- **More newsletter images load.** With remote images allowed, images
  addressed with `http://` or `//host/…` are now requested over https, as
  Gmail does. An image that still fails shows its alternative text in small
  type, when it has one, instead of leaving an empty space.

- **Fixed: a closed parent label kept showing the open sublabel.** Closing
  a parent label now hides everything under it, as in Gmail; "Less" still
  keeps the open view visible.

- **OpenPGP (off by default).** Signature check and decryption of PGP/MIME
  and cleartext-signed mail, with an indicator in the message header, and
  Settings → OpenPGP keys, behind the `DREAMAIL_PGP` build switch (empty by
  default). Public keys in the encrypted database, secret keys in the
  Keychain. A key is stored only after a confirmation that shows its
  fingerprint and every address it claims. The rPGP-based library from
  `dreamail-openpgp` is now linked into the app also when the switch is off;
  with the switch off nothing reaches it and nothing is shown. Mail encrypted by
  GnuPG 2.4 with its default settings is decrypted too (library v0.1.1).

- **Sidebar like Gmail.** System views in Gmail's order with Important, a
  "More" row (Scheduled, Reminders, Promotions, Social, Spam), and your labels as a
  tree with colours, unread counts and Gmail's show/hide setting. "+" next to
  Labels creates a label, also nested. Outbox and Reminders stay visible when
  they hold something. Spam shows what this Mac has: spam received since the
  account was added; older spam stays on Gmail. The all-labels view moved to
  Go ▸ Labels (`g l`). Switching account while a label is open goes to the
  Inbox.

- **The window reopens as you left it.** At launch the main window comes back
  with the size and position it had when it was closed.

- **Account rail.** An always-visible strip left of the sidebar shows one
  avatar per account with its unread count, "All accounts" when there are
  several, "+" to add an account, and Settings at the bottom. It replaces the
  account switcher and the Settings row in the sidebar; ⌘1…⌘9 work as before.
  A window narrower than 1144 pt now uses the compact layout. The rail is
  a narrow 64 pt strip under a band of the same colour that runs along the
  top, from the window's left edge over the close, minimise and zoom buttons
  to the right edge of the sidebar, so the window buttons sit fully on it
  without a wide rail. "All accounts" has a thin grey ring while it is not
  selected, and Settings → Appearance can hide the "+" (accounts can always
  be added in Settings → Accounts).

- **Label picker like Gmail.** Enter applies the highlighted label and
  closes the picker; Space ticks or unticks a label and keeps the picker
  open, like a click; Esc closes it. "Create new" at the bottom creates a
  label without leaving the picker.

- **A remote image that fails to load is hidden.** With remote images allowed,
  a failed image without alternative text now shows nothing, as in Gmail,
  instead of a blue "?" icon. Images with alternative text are unchanged.

- **Mail appears while the first sync runs.** After adding an account (or
  widening "Keep mail from") conversations show up as they are downloaded,
  the Inbox and the newest first, and can be opened, archived, starred,
  labelled or deleted at once; before, the list stayed empty until the whole
  period had been downloaded, and anything done during the download was
  undone. A sync cut short (quit, no network) resumes where it stopped and
  keeps what you did meanwhile. Old mail downloaded this way does not post
  notifications. "Connecting…" now ends as soon as the account is saved, and
  while DreaMail waits for the browser there is a Cancel.

- **Escape closes every dialog, and shortcuts stay out of the way.** While a
  sheet or an alert is open (new label, Organize Labels, filters,
  signatures, the label menu's dialogs) the keys go to it: Escape closes it,
  and the mail shortcuts no longer act on the window behind. With compose's
  "Discard" confirmation open, Escape now cancels the confirmation.

- **Categories without a sub-menu.** Under "More", Promotions and Social are
  plain rows just above Spam; the "Categories" group is gone.

- **The open conversation and mailbox keep their colour.** On macOS 26 the
  selected row in the list and in the sidebar stays in the accent colour
  when you click elsewhere or the window is inactive, as in Gmail: the
  colour means "this is open", not "this list has focus" (it used to turn
  a heavy grey). In the sidebar, in Settings and in the collapsed icon
  strip the selection is a square band like the one of the message list,
  reaching the list's edge, the same with and without focus; the sidebar
  shows no scroll bar. On macOS 14 and 15 the system's selection stays. Also: the
  "+" next to Labels is larger and neutral, the label "⋮" is vertical and
  neutral (not accent blue), the hover actions on a conversation row have
  a little more space between them, and the "Defaults" table in Settings →
  Signatures is aligned.

- **A hidden sidebar becomes a strip of icons.** Hiding the sidebar no
  longer removes it: it shrinks to a narrow strip next to the account rail
  with the icons of Search and of your mailboxes (in your order) down to
  "More", as in Gmail's collapsed navigation. Click an icon to open that
  mailbox; the unread count is in the tooltip; Search reopens the sidebar
  with the search field active; "More" shows the mailboxes under it. Labels
  and saved views are in the full sidebar only. Narrow windows and the
  full-window conversation behave as before.

- **Reorder the sidebar; a closed "More" hides everything under it.** Drag
  the system views (Inbox, Starred, Sent, Promotions, Reminders...) to
  reorder them, also across the "More" row: drop one above "More" to keep
  it always listed, below to tuck it away. The order is kept per account
  (the all-accounts view has its own); "Reset Sidebar Order" (View menu, or
  right-click a view) restores Gmail's. With "More" closed nothing under it
  is listed, the open view included; the same holds for the labels' "More".
  Reminders is still listed above "More" while something has a reminder.

- **List and sidebar density.** Settings → Appearance has "List density"
  and "Sidebar density", each Comfortable (as before) or Compact. Compact
  trims the space above and below each row (a conversation row is 8 pt
  shorter, a sidebar row about 7 pt shorter); fonts, icons and the section
  headers ("Today", "Yesterday"...) keep their size.

- **Snooze understands English day and month names on any Mac.** With the
  Mac set to another language, "fri", "sat", "sep 5" gave no suggestion.
  English names now always work, and those of the Mac's language still do
  ("ven", "set 12", also without accents: "venerdi"); suggestions are
  titled in English. "mar 5" on an Italian Mac offers March 5 first.

- **New mail in a conversation you had deleted shows up again.** A
  conversation counted as deleted as soon as one of its messages was in the
  Trash, so a reply arriving later stayed hidden there, missing from Inbox
  and All Mail. As in Gmail, a conversation is in the Trash only when all
  its messages are; new mail brings it back with the new message only: the
  messages you deleted stay out of the conversation, of search and of the
  counts. Conversations hidden this way come back at the first sync after
  updating.

- **The Trash shows deleted messages of conversations that are still
  alive.** As in Gmail, the Trash (and `in:trash`) also lists a conversation
  when only some of its messages are deleted; opened from there it shows
  just those messages. "Move to" from the Trash restores only them and
  leaves the rest of the conversation alone; the other commands are off
  for such a row. Undo after moving a conversation to the Trash brings back
  what that action deleted, never the messages you had deleted before. If
  Gmail refuses a restore, the message goes back to the Trash here too and
  an error says so.

- **A message that could not be downloaded is tried again.** When the
  download of a single message failed during a sync, the sync moved on and
  the message never arrived (a conversation could show an older time than
  Gmail, its latest message missing). Such messages are now remembered and
  retried on later syncs; if some still cannot be downloaded, the sync
  indicator and Settings → Accounts say how many.

- **The sync indicator tells the truth.** The "last synced" time in the
  toolbar and in Settings → Accounts is refreshed as time passes (it could
  read "now" for hours) and says "Sync failed · last synced …" when the
  last pass of an account failed.

- **Labels in the sidebar as in Gmail: whole families, Gmail's order.** A
  label and its sublabels always stay together, nested: the whole family is
  listed above the labels' "More" or below it, following the top-level
  label's setting in Gmail (a "show if unread" family shows up when any of
  its labels has unread mail). No label appears twice and none is shown as
  "parent/child". Labels are in Gmail's order (symbols and emoji first,
  upper and lower case mixed) unless you reordered them in Organize Labels.
  Every order stored by earlier versions is dropped once, when you update
  (an older version stored one for all labels on any drag, so it could not
  be told from a deliberate one): reorder again if you had done so on
  purpose. Dragging a label in Organize Labels now fixes the order of its
  own group only, and "Use Gmail's Order" there goes back to Gmail's. A
  label deleted on Gmail leaves nothing behind on this Mac.

- **Label colours.** A label without a colour is drawn as an outline only,
  so any filled tag has a colour (a dark grey one no longer looks like "no
  colour"). For labels that Gmail's label list returns without a colour,
  the label is read again in full, since the list is not guaranteed to
  carry colours.

- **Fixed: two colours behind the sidebar button in light appearance.**
  With the sidebar reduced to the icon strip, the band at the top of the
  window was grey above the account bar and the strip and white above the
  message list, and the seam ran behind the sidebar button. In light
  appearance, with the sidebar reduced, the whole top bar now has the grey
  of the account bar, from the window buttons to the right edge, as dark
  appearance looks; it stays grey when a conversation fills the window.
  Dark appearance and the open sidebar are unchanged.

- **The unified inbox can be switched off.** Settings → Appearance →
  "Show unified inbox (All accounts)", on by default. Off, the "All
  accounts" button leaves the account bar, ⌘1, ⌘2… select the accounts in
  order, and the app opens on the first account instead of the unified
  view. Saved views that cover all accounts are hidden while it is off and
  come back when it is on again (a view created with the unified inbox on
  covers all accounts, also when you had a single account); a view you
  create while it is off belongs to the account on screen. Unread badges,
  the Dock badge and notifications do not change.

- **Fixed: mail in Gmail's Promotions and Social categories was missing
  from the Inbox.** The Inbox hid those two categories by default, so new
  mail that Gmail shows in the Inbox could be found only under "Social",
  "Promotions" or All Mail, and it was left out of the Inbox unread count,
  the Dock badge, the account badges and new-mail notifications. The Inbox
  now lists every conversation that has the Inbox label, whatever its
  category, and counts and notifies the same conversations. Nothing was
  ever archived or changed on Gmail. A category filter you turn on
  yourself (the Labels / Filter chips) still hides that category, except
  starred conversations; turning it off again does not notify old mail as
  new. If you had stored an Inbox filter hiding Promotions or Social, it is
  cleared once when you update (it cannot be told from the old default):
  set it again if you want it. Saved views keep the filters they were
  saved with, so a view saved from the Inbox with an earlier version still
  hides the two categories until you save it again. Expect more
  notifications: promotional mail in the Inbox now notifies too.

- **The search field is in the top bar.** It moved from the sidebar to the
  bar at the top of the message list, to the right of the view's icon and
  name, and narrows with the list when there is less room. It works as
  before: click it or press `/`, Esc leaves it, and the results panel
  opens under it. With the sidebar reduced to icons, its Search button now
  puts the cursor in that field instead of reopening the sidebar. The
  "»" button at the right of the reading pane's bar is gone: it did the
  same as the button that shows and hides the reading pane.
- **Actions on a single message, as in Gmail.** Every open message in a
  conversation now has, after its date: Star, Reply, Reply all (when it
  differs from Reply) and a More (⋮) menu with Reply, Reply to all,
  Forward, Filter messages like this, Delete this message, Block sender,
  Report spam, Show original, Download message and Mark unread from here.
  The star is on that message only. "Delete this message" moves only that
  message to the Trash: the conversation stays where it is while another
  message remains, shows "1 deleted message in this conversation", and the
  deletion can be undone. An open message is closed from its date.
  Not included: Print, Add sender to Contacts, Report phishing, Translate.
- **A conversation with starred messages opens on them.** The newest
  starred message is open and in view, together with the newest message
  and the unread ones (five at most); unread mail newer than the star
  comes first. Without stars a conversation opens as before.
- **Fixed: two rows highlighted in the sidebar.** After some changes of
  view (for example from a row under "More", or with a keyboard jump), the
  sidebar could show the highlight on two rows, the new view and the one
  left behind. Only the row of the view on screen is highlighted now.
- **More actions in the selection bar.** With several conversations
  ticked, the bar now also offers, in Gmail's order: Archive or Move to
  inbox, Report spam (Not spam in the Spam view), Trash, Read/Unread,
  Snooze, Move to…, Label as… and Star. In a narrow list the last ones
  move under a "More" (⋮) button.
- **"Label as…" works on several conversations.** Opened from the bar,
  from the right-click menu on ticked rows or with `l`, it shows a tick for
  a label all of them have and a dash for a label only some have; a click
  adds the label to all, or removes it when all had it. The change can be
  undone. Conversations of another account are left out, with a notice.
- **The selection bar shows icons.** With several conversations ticked,
  the bar above the list now has icon buttons for Archive, Trash, Star and
  Read/Unread, as in Gmail, instead of text. Each has a tooltip with its
  name and shortcut. The Star and Read icons show what the click will do
  for the ticked conversations, and a button that would do nothing is
  greyed out. The Trash icon is no longer red.
- **Promotions and Social can be turned off per account.** Settings →
  Accounts has a new switch for each account, "Show Promotions and
  Social", on by default. Off, that account has no Promotions and Social
  rows in the sidebar, no such choices in the filters and no such chip on
  a conversation. No mail is hidden: everything stays in the Inbox, in
  All Mail, in search, in the counts and in notifications. In "All
  accounts" the two rows are shown while at least one account has them
  on, and list only those accounts' mail. Saved views are not changed.
- **Move to inbox.** A conversation that is not in the Inbox (archived,
  or reached from a label, All Mail or a search) can be moved back, as in
  Gmail: "Move to inbox" takes the place of Archive in the conversation
  toolbar, on the row (hover button, swipe, right-click menu), in the
  Message menu and in the command palette. "Move to…" lists Inbox first,
  and typing "inbox" in "Label as…" offers the move instead of creating a
  label with that name. The move ends a snooze, unmutes the conversation
  and can be undone. There is no default key, as in Gmail; one can be set
  in Settings.
- **The right-click menu on a conversation follows Gmail's.** Same order,
  groups and wording, with an icon on every item: Reply, Reply all,
  Forward; Move to inbox or Archive, Delete, Mark as unread or read,
  Snooze; Move to…, Label as…, Mute or Unmute; Find emails from the
  sender. The app's own items (Star, Remind me, VIPs, Copy Gmail link)
  come after. Right-clicking one of several ticked conversations acts on
  all of them. Not included: Forward as attachment, Add to Tasks, Open in
  new window. "Find emails from" is not offered when the sender's address
  contains `_`, `%` or `*`.
- **The label colour sheet also shows Gmail's colour preset.** Some labels
  that have a colour in Gmail on the web arrive from Gmail with no colour,
  or with a neutral grey, and were drawn uncoloured. The app now also reads
  the "preset" Gmail may attach to a label, shows it in the "Current:"
  line ("preset DARK_GREEN", "unknown preset", or "no preset (list and
  get)" / "(list only)" when Gmail sent none), and draws the label with
  that preset's colour when Gmail's own colour is missing or the neutral
  grey. Such labels are read one by one, at most every six hours. Whether
  Gmail really sends the preset to this app is not known yet: the missing
  colours are not reported as fixed. Removing a colour that Gmail keeps as
  a preset now says so instead of reporting success.
- **The label colour sheet says what is stored.** "⋮" → Label color →
  Choose color now shows a line "Current: #rrggbb" (with the text colour,
  and "not in this palette" when the colour is not one of the swatches
  offered) or "Current: none", for the colour on Gmail and for the one
  picked only on this Mac. The sheet offers 64 of Gmail's colours, so a
  label can have a Gmail colour with no swatch ticked. In dark appearance a
  very dark label colour (a dark grey, black) is lightened in the sidebar
  just enough to be seen, instead of a nearly invisible fill with an
  outline that looked like "no colour"; light appearance is unchanged.
  Known open point: some labels with a colour on Gmail are still drawn
  without one, and the cause is not known yet.

- **Sidebar and Settings touch-ups.** The Settings window is titled just
  "Settings". The "+" next to Labels has the size of the
  "+" of "Add view"; the label "⋮" is three small dots. In Settings →
  Signatures the "Defaults" menus are left-aligned and equally wide.

- **The Dock badge goes away when you quit.** The unread count stayed on
  the Dock icon after quitting; it is now cleared at quit, and at launch if
  a crash or force quit left one behind.

- **Organize Labels keeps families together.** In Organize Labels the
  sublabels are listed under their label, indented. Dragging a label moves
  it with all its sublabels; a sublabel can be reordered among its siblings
  but cannot be dragged away from its label, and a label cannot be dropped
  inside another family. The label picker and the Labels view list labels
  in the same order.

- **Labels like Gmail: the label menu.** Each label in the sidebar has
  Gmail's menu, on "⋮" (shown on hover and on the open label) and on
  right-click: label colour, show in label list (show, show if unread, hide),
  show in message list (show, hide), edit (rename, nest under another label),
  remove, add sublabel, and Organize Labels. Changing a parent label's colour
  changes its sublabels too, at any depth; the colour picked last is the one
  shown, and a new sublabel takes its parent's colour. Renaming or moving a
  parent takes its sublabels with it; removing a label removes its sublabels
  and the saved views that show it, after a confirmation that names them
  (conversations are kept). A label hidden "in message list" no longer shows
  its chip in the thread list. Label edits need a connection: offline, the
  action says so and does nothing.

- **Signatures follow Gmail by themselves, with their look.** The signature
  set in Gmail for each sending address is copied in automatically (at
  launch, when an account is added, and when a compose window opens, at most
  every five minutes); "Import from Gmail" is gone. A Gmail signature becomes
  the default for new messages only when none is set; the default for
  replies stays yours to choose in Settings → Signatures. A signature you
  wrote here is never overwritten or deleted by Gmail; one removed on Gmail
  stays, marked "No longer on Gmail". The compose window has Gmail's pen menu
  to pick a signature or none. The message is sent with the signature's
  formatting from Gmail (fonts, colours, links, tables; images are dropped)
  as long as you did not edit the signature. In the compose window such a
  signature is shown once, as a read-only block with that look, under the
  text; "Edit signature as text" in the pen menu turns it into plain text
  you can change (it is then sent as typed).

- **Your own messages show the right account's photo.** With two accounts
  that share a sending address (one account's address is a "send as"
  address of the other), a message you sent showed the other account's
  profile photo. It now shows the photo, or the initial, of the account the
  message is in.

- **Pasting a signature copied from Gmail.** In Settings → Signatures, ⌘V
  of a signature copied from Gmail's settings page (into an empty box, or
  over the whole text) keeps its look: fonts, colours, links and tables;
  images are dropped. The sheet shows the look above the text; editing the
  text, or "Remove formatting", makes it a plain signature. For the Gmail
  signatures the API does not hand over (it gives one per address).

- **Signatures per account.** DreaMail → Settings (⌘,) → Signatures: several
  signatures per account, a default for new messages and one for replies per
  sending address, and import of the signatures already set in Gmail. The
  compose window inserts the right one, replaces it when From changes, and
  has a menu to pick another or none. Text typed under the signature is never
  removed.

- **Fixed: messages with slow or missing remote images.** A message whose
  remote images are slow or gone now opens at its full height at once, instead
  of a clipped box for up to 30 seconds. Images still loading are no longer
  shown as failed, and DreaMail's own copy of the images for later opens is
  fetched only after the message view has finished loading.
- **Notification details per account.** "Show sender and subject in
  notifications" is now chosen for each account in Settings → Accounts.
  Existing accounts keep your current choice; new accounts start off. Switching
  it off withdraws that account's notifications from Notification Center. Gmail
  filters show one account at a time, and the Settings sidebar separates
  per-account settings from app settings.
- **Darker date headers in the thread list.** "Today", "Yesterday", "Last 7
  days" and the other section headers use the primary text colour.
- **`make run` starts with the real account.** The fictional demo inbox now
  needs `make run DEMO=1` or `make demo`.
- **Row actions on hover, star on the left.** With the pointer on a
  conversation, archive, trash, mark as unread or read and snooze appear at the
  right end of the row, in this order, as in Gmail. The star now sits to the
  left of the sender.
- **Unread count on each profile photo.** The account rail shows each
  account's unread count as a badge in the top-right corner of its photo ("99+"
  above 99). The badges add up to the Dock badge when that counts all accounts.
- **Google Calendar interface (off).** Behind the `DREAMAIL_CALENDAR` build
  switch (empty by default): connect Calendar per account and choose the
  calendars that count (primary by default) in Settings → Accounts; on an
  invitation, see whether you are free, add it to your calendar, and have your
  answer saved there after the e-mail reply. Nothing changes in the app.
- **Snooze aligned with Gmail.** Conversations snoozed in Gmail on the web or
  the phone now appear under Snoozed (Gmail still wakes them). Removing an
  account first deletes its data, then puts its DreaMail snoozes back in the
  Gmail Inbox within ten seconds; what could not go back is reported. A
  conversation moved back to the Inbox elsewhere reappears at once; a snoozed
  conversation that is trashed or marked spam no longer comes back.
- **Google Calendar groundwork (off).** Behind the `DREAMAIL_CALENDAR` build
  switch (empty by default): a separate consent, availability next to an
  invitation, the answer also written on the calendar (the e-mail reply is
  always sent), add to calendar. Only the Calendar grant and the chosen
  calendars are stored, encrypted and deleted with the account. Nothing changes
  in the app.
- **OpenPGP groundwork (off).** Recognition of OpenPGP/MIME and inline
  messages, exact signed-byte extraction, and the security and rendering rules,
  behind the `DREAMAIL_PGP` build switch (empty by default). No library, no
  interface and no change in behaviour yet.
- **Gmail filters can be edited.** Filters can now be created, edited and
  deleted in Settings → Gmail filters, with an approximate preview of the
  matching mail on this Mac and a confirmation before saving a filter that
  deletes mail or hides it from the Inbox. Gmail has no update call, so an edit
  creates the new filter and then deletes the old one; if the delete fails both
  are listed. Forwarding filters are still edited in Gmail.
- **More Gmail shortcuts.** Mute (`m`), mark as important or not important (`+`
  or `=`, `-`) and move to (`v`, which also leaves the current label or Trash),
  each with undo, also in the Message menu, the command palette and the
  conversation's More menu. Inside a conversation: next and previous message
  (`n`, `p`) and expand or collapse all (`;`, `:`). The `?` help lists the
  compose formatting keys. Mute relies on a Gmail label the API may refuse; if
  it does, the conversation comes back with a message.
- **Label colors on Gmail.** In the label organizer you can change a label's
  color on Gmail (from Gmail's own palette, so the web and the phone show it
  too) or remove it, separately from the Mac-only color, which still wins on
  this Mac.
- **Safer calendar invites.** A hostile or malformed invite can no longer slow
  the app down, and a reply goes only to the single organizer, who is always
  shown together with the identity you answer from. The reply is rebuilt from
  checked fields and never copies lines the sender wrote. Updated invites ask
  again and never show an answer given to another organizer; repeating events
  and received replies are labelled. Answers are stored in the encrypted
  database and deleted with their message; answers given before this change are
  forgotten, so those invites show their buttons unselected again.
- **Fewer duplicate CI runs.** A change that touches only documentation
  (`docs/`, `reviews/`, `.claude/`, `CHANGELOG.md`, `CLAUDE.md`) no longer
  runs the macOS build and tests, on its pull request into `main` or on
  `main`. Only `main` saves the build cache. On `main`, runs for different
  commits no longer cancel each other, so every merged commit is tested.
- **Remote images are kept after the first open.** Remote images of messages
  you open with images allowed are now kept encrypted with the message, so
  later opens (also after a relaunch) usually show them without asking the
  sender. The first time you open such a message, the sender is asked twice for
  each image (once by the message view, once by DreaMail to keep a copy);
  images a sender makes uncacheable still load from the sender every time.
  Nothing is downloaded for mail you have not opened.
- **Accent colour setting.** Settings ▸ Appearance ▸ Accent color picks the
  colour for selected rows (sidebar, Settings, message list; macOS 26 and
  later), buttons, links, badges and highlights, live in every window; Default
  keeps DreaMail's blue and the system selection colour. Text on the accent
  turns white or black to stay readable (4.5:1), and accent text on the app's
  backgrounds is darkened or lightened just enough to stay legible.
- **Dock badge follows your actions and tells you when macOS hides it.**
  Reading, archiving, deleting or snoozing a conversation updates the unread
  count on the Dock icon immediately, also for accounts not shown in the
  sidebar, and it is repainted when you return to the app; above 999 it reads
  "999+". Settings ▸ Dock badge shows whether macOS allows the badge, with a
  button to System Settings ▸ Notifications.
- **Remote images now load by default when you open a message.** Opening
  includes moving to a conversation in the list while the reading pane is
  showing, and landing on one after archive or delete. The sender can then see
  that you opened the message and when, your IP address and your mail client.
  Installs that never chose a setting follow the new default; a stored choice
  is kept. To go back, choose Settings → Appearance → Load remote images → Ask
  each time (or VIP senders). Exceptions: mail in Spam never loads remote
  images without its own click, conversations you have not opened are never
  loaded in advance (the background pre-render stays blocked), and holding an
  arrow key opens only the conversation where you stop. `SECURITY.md` has a new
  "Remote images" note.
- **Inline images survive a relaunch.** Inline images of a conversation you
  opened before now appear without downloading again, even after quitting: they
  are kept in the encrypted local database (up to 200 MiB, least recently used
  out first) and deleted with their mail.
- **Conversations read like Gmail's.** In the reading pane the messages of a
  conversation are flat rows (avatar, bold sender, date, one-line snippet)
  split by a hairline, instead of cards; opening a message keeps its header in
  place.
- **Label chips shaped like Gmail's.** A compact rounded rectangle in the
  label's colour, with no outline (kept only on near-white labels, on the
  selection highlight when a chip would blend into it, and on colour dots).
- **The account's colour is a ring, its label is its title.** The account's
  label colour is now a 3 pt ring around its avatar, and the label (e.g.
  "Work") is the account's title in the switcher and Settings instead of the
  sender name; the colour can be chosen even without a "Send as" name. The
  account pill is gone.
- **Crisper, monochrome sidebar icons.** Sidebar and Settings sidebar icons
  are drawn at the row title's size, in medium weight, so they read less soft
  and large; they follow the "Sidebar icon size" setting in System Settings ▸
  Appearance. The selected row's icon is the filled glyph in the text colour
  (white on the accent selection of a focused sidebar), no longer tinted with
  the accent colour, in active and inactive windows and with any accent
  colour.
- **Account photos.** The account switcher and the Accounts settings show each
  account's own Google profile photo instead of the initial disc. The photo
  URL comes from the profile DreaMail already reads (no new permission, no
  new sign-in); the image is fetched only from Google's photo hosts, without
  the account's token, at sign-in and then at most once a day, and kept
  downscaled in the encrypted database with the account. Removing the account
  deletes it. For an account without a photo Google usually returns a
  generated letter image, and that is what is shown. The initial disc stays
  until a first photo is stored (so also while fetches fail), when Google
  gives no usable photo, and in demo mode.
- **CI fails on compiler warnings and checks the scripts.** A Swift or C/ObjC
  warning in the app, relauncher or unit tests fails the CI build (the UI-test
  target is not gated; local builds are unchanged). Release binaries are
  still built without the flag, but the CI run that `make release` waits for
  fails on warnings, for example a new deprecation after an Xcode update on
  the runner. The Python tests of the helper scripts run on every push, and
  shellcheck covers every shell script. `make checks` runs the Linux checks
  locally.
- **Choose the colour of each account's label.** "Edit Account Labels…" now has
  a colour per account: the system colour picker, the label organizer's
  swatches for one click, and "Default" (the avatar's hue). The colour is drawn
  as a ring around the account's avatar, with a thin outline when it is close
  to the background. The colour stays on this Mac, is never sent to Google, and
  is removed with the account.
- **Faster first open, and inline images are not downloaded twice.** The first
  conversation you open is ready sooner, and re-opening a conversation with
  inline images no longer downloads the images again. Deleted mail leaves the
  in-memory reading cache at once.
- **Spell check in several languages at once.** Settings ▸ Spelling and
  grammar ▸ Check spelling in ▸ Specific languages (for example English and
  Italian). Each paragraph is checked in its own language, and a word spelled
  correctly in any chosen language is not underlined.
- **Compact section breaks in the thread list.** Between "Last 7 days",
  "Last 30 days", "Older" and the other sections there was an empty band about
  two rows tall. The next header now follows the last row after a small gap,
  scaled with the list's font size.
- **Label colours you can read, as in Gmail.** Label pills are drawn in the
  label's Gmail colour as a solid fill, with Gmail's text colour when it is
  readable on it (4.5:1) and black or white otherwise. Only near-white labels
  get a thin grey outline on a light row; on the selection highlight a chip
  that would blend in gets one too. Colours changed in Gmail now show after the
  next sync; a colour picked in the label organizer still wins, and "Gmail
  color" goes back to Gmail's. Labels with no Gmail colour and no colour picked
  here are neutral grey, as in Gmail. Same rule for the reading pane, the
  Labels filter, the label picker and the organizer.
- **A single message opens at its full length.** Selecting a one-message
  conversation no longer shows a reduced card first: the message is open from
  the first frame, fills the reading pane while it loads, and stays open. A
  message seen before, or pre-rendered while browsing, appears at its full
  height without growing.
- **Monochrome sidebar icons, as in Gmail.** Sidebar, Settings-sidebar and
  list-header icons are grey outline glyphs; the selected view gets the filled
  glyph, a darker tint and a semibold title. Colour stays for label colours, the
  starred star, badges and warnings.
- **Deleted mail is gone, not just hidden.** Deleted content is overwritten in
  the mail cache and removed from the search index when it is deleted, and old
  copies are cleared from the cache's write-ahead log within seconds of a
  deletion and at least every five minutes. A deleted message's opened
  attachment copies and its conversation's notification go with it. Gmail
  responses are no longer written to an on-disk HTTP cache, and the old cache
  files are removed. `SECURITY.md` has a new section, "What deleting means",
  with what this does and does not cover (SSD and backup copies, the short
  window before clean-up, files handed to other apps).

- **Default shortcuts and layout follow Gmail on the web.** `u` now goes back
  to the conversation list (it was mark read/unread: use Shift-I / Shift-U,
  which now only mark read / unread, or bind the toggle again in Settings), `o`
  opens, `]` / `[` archive the open conversation and move on, Shift-N
  refreshes, `g b` and `g l` go to Snoozed and Labels, `*` then a / n / r / u /
  s / t selects, and ⌘⇧C / ⌘⇧B / ⌘⇧F / ⌘⇧9 work in compose. The default for
  opening a conversation is now the reading pane beside the list, also on
  installs that never chose a style (a stored choice is kept); browsing with
  j/k therefore opens each conversation, which marks it read sooner and, with
  the default image setting, loads its remote images (see the remote-images
  entry above). Custom keys are kept; a new default that collides with one is
  left unbound.
- **AI features and the local MCP server are off.** A build setting
  (`DREAMAIL_AI_FEATURES`, empty in the tracked configuration) decides it, not
  a preference. Off means no Ask AI, summaries, AI drafting, suggested
  replies or AI sorting, no request to any model provider or to Ollama, no
  stored provider credential read, and no MCP listener even if an earlier
  build had it enabled. Install and release builds take the setting from the
  tracked configuration only and check the built app. The code is kept. For
  when it is turned on again: a saved key or sign-in is only ever sent to the
  origin it was entered for, consent is tied to scheme, host and port,
  cross-origin redirects are refused, and the helper scripts refuse plain HTTP
  to anything but a loopback address.
- **Removing an account now removes everything of it.** Besides cached mail and
  the sign-in: opened attachment copies, saved views for the account, snippets
  available only to it, its sync and filter settings, its notifications, recent
  searches, and Ask AI chats that may contain its mail. The confirmation
  lists all of this. If the removal fails nothing is deleted and you are told;
  a removal interrupted by a quit is finished at the next launch. The advice to
  remove and re-add an account to grant the filters permission is gone: signing
  in again is enough.
- **Notifications are generic by default.** "New mail", "Follow-up reminder" and
  "Scheduled message sent" with no sender or subject. Settings → General →
  Notifications has a switch to show sender and subject; the message preview is
  never shown.
- **Errors in the system log carry no mail data.** Database, sign-in and
  text-layout errors log an error type and code, not SQL text, file paths or
  text from the message being written; a failed launch no longer writes them
  to the crash report. Gmail errors in banners show the status, the reason and
  Google's one-line message (up to 160 characters) instead of the raw response.
- **The database dependency is pinned by commit.** GRDB with SQLCipher is fixed
  to an exact commit instead of a tag, and CI and release builds download it
  afresh so its checksum is verified every time. `docs/DEPENDENCIES.md` records
  where it comes from and how to upgrade it.
- **This fork has its own identity and its updater is off.** Bundle
  identifiers are now `io.github.bateman.*`, so the app keeps its own
  container, settings and Keychain items and starts fresh: nothing is migrated
  from a `dev.ronboger.MishMail` install (the README lists the cleanup steps).
  The in-app updater does nothing unless a release channel is configured at
  build time, and stays off on any copy without a Team ID even then. An update
  must carry the installed app's bundle identifier.
  `scripts/update-dreamail.sh` needs `--repo`, refuses anything not strictly
  newer unless `--allow-downgrade` is passed, checks the signature against the
  installed app's identifier and Team ID, and downloads over HTTPS from that
  repository's releases only.
- **An old unencrypted mail cache is never written to again.** When a legacy
  plaintext cache cannot be encrypted at launch (another copy is running, or
  the file is busy), DreaMail opens it read-only: sync, queued edits,
  scheduled sends and draft saves pause, a strip that cannot be dismissed says
  so, and account or settings changes are refused with a notice. A cache too
  old to read without migrating shows "Finish encrypting your mail" instead of
  an empty mailbox. The next launch retries the encryption.
- **The diagnostic log no longer holds addresses or server replies.** It
  records a per-install account tag, the request path without identifiers, the
  status and Google's reason codes. The file is private to your user, rotates
  at 512 KiB or 7 days, and a log from an earlier version is deleted at
  launch. Entries already in the macOS unified log from earlier versions
  cannot be removed and age out with the system's retention.
- **Sign-in can no longer be stalled by idle local connections.** The
  temporary sign-in listener allows 16 connections, closes each after 10
  seconds, makes room for a new one by closing the oldest that has sent
  nothing, and closes them all when sign-in ends.
- **CI runs with a read-only token and pinned tools.** Actions are pinned to
  commit SHAs (Dependabot keeps them current), XcodeGen is a checksummed
  2.46.0 release, a skipped test that is not on the allowlist fails the job,
  and a check fails the build if a workflow loses its pins or its
  `permissions` block.
- **The compose caret-scroll tests no longer fail on a slow runner.** They
  waited a fixed 150 ms for a scroll the editor defers by 50 ms; they now wait
  for the deferred scroll itself.
- **Notion Mail is gone from the app.** The "Moving from Notion Mail" pane,
  its Cmd-K entry and the onboarding callout are removed. Snippet import reads
  only DreaMail's own format: a JSON array of objects (or one object) with
  `name` and `body`, or CSV with `name` and `body` columns. It no longer
  unwraps `{"snippets": […]}` files, guesses other key or column names, or
  rewrites `{{First Name}}`-style variables. A newly imported `{{First Name}}`
  (or `{firstname}`, `{today}`, `{sender}`…) is sent as literal text, with no
  warning; snippets imported earlier are unaffected. Compose still expands
  `{first_name}` and `{{first_name}}`.

- **A draft no longer disappears from Drafts while you write it.** Each
  autosave removed the old draft from the local mailbox and wrote nothing new
  until compose closed. A new-message draft vanished from the Drafts list, and
  a reply draft's conversation dropped out of Drafts on the next list refresh.
  Autosave now stores the saved draft from Gmail and drops the old one in one
  step, so the row and the open conversation stay in place.
- **A conversation shows that it has deleted messages, as Gmail does.**
  When some messages of a conversation are in the Trash and others are
  not, the reading pane shows the line "N deleted messages in this
  conversation" with "View". "View" shows them in place, dimmed and marked
  "In Trash"; "Hide" puts them away again. Each has "Restore", and the line
  has "Restore all": they take the messages out of the Trash on Gmail and
  back into the conversation. A deleted message shown this way loads no
  remote images until you ask, and is not checked for OpenPGP. Deleted
  messages stay out of the list row, search, counts, quoted replies and
  the assistant.

## [0.7.0] - 2026-11-13

- **Compose links now read naturally** — links with display text render as the
  blue underlined label in the editor; MishMail no longer exposes the backing
  `[label](URL)` syntax while drafting. Draft storage, ⌘K editing, and sent HTML
  remain unchanged.
- **Spell check no longer rewrites words.** Compose marks a wrong word with
  the red underline and offers corrections on right-click, but it never
  changes text by itself.
- **Return in compose no longer flickers.** The body scrolled down one line
  and snapped back each time a new line made the editor grow.
- **Fixed a crash after typing in compose.** A text layout error during a
  system correction popup could crash the app on the next key press.
- **The thread view no longer shakes after a message opens.** Mail sized in
  viewport units (`vh`, `vmin`) made each message card resize itself several
  times. The reading pane now pins those units once, so a card settles at one
  height.
- **Bcc'd mail now shows which of your addresses it reached.** When To and Cc
  name none of your addresses (Bcc, a mailing list, a forward), the message
  header adds a "VIA" row with the address from the `Delivered-To` chain.
  Reply and the unsubscribe email now send from that address when it is one
  of your send-as aliases.

## [0.6.1] - 2026-11-07

- The reading pane tracks message height and scroll position for inline reply pinning only while that feature needs them.
- Inbox date grouping reuses calendar boundaries across rows. Typo-tolerant search compares fewer characters, and plain-text messages with many links take less work to prepare.

## [0.6.0] - 2026-11-07

### Added
- Ask Mish supports GPT-6 tool conversations, with model, thinking, speed, and new-chat defaults in the model picker.
- **AI draft in compose.** Give a short instruction ("ask for two more
  days"); the draft streams into a separate preview. **Use draft** applies
  it and **Undo** restores your text. Rewrite, shorten and tone changes work
  on a selection or the whole draft.
- **How I write** (Settings → AI): set tone, sign-off or a booking link once.
  Drafts, suggested replies and Ask Mish use it.
- **Summaries know when they are stale.** A saved thread summary is flagged
  for Refresh when a new reply arrives.
- **Paste a recipient list.** A pasted list (commas, semicolons, new lines,
  or a column of addresses) becomes one chip per mailbox, without
  duplicates. A comma inside a quoted name no longer erases what you typed.
- **Clickable links in plain-text mail.** Web links and addresses in a
  plain-text body open in the browser or a new message.
- **Cmd-K acts on checked conversations.** Archive, Trash, Star, Mark Read,
  Snooze and Label in the palette apply to the whole selection.

### Fixed
- Failed draft saves keep the editor open. Scheduled sends take ownership of offline drafts when the queue write succeeds.
- Undo Send and Ask Mish confirmations act on the specific message or action shown.
- Saved views resolve conflicting filters, and overlapping searches and syncs keep their own progress.
- Gmail sync now paces each account for the 6,000-unit minute limit on new
  Google Cloud projects and counts each message in a batch at its format-specific cost.
- **Compose no longer hides the last lines of a reply** at a larger text
  size. The body is sized from the real text layout.

### Changed
- The inbox, composer, and message reader have more space. Selectable plain-text links use the app accent, and mail from your own address can show its configured sender name.
- **Faster everywhere.** A performance pass across launch, the thread list,
  the reading pane and sync:
  - The mail cache now uses its encryption key directly instead of running
    a 256,000-round key derivation on every database connection (about
    75 ms each). The first launch after updating converts the file once,
    which takes a few seconds on a large mailbox.
  - Inbox, Promotions, Social and per-account lists sort from an index
    instead of sorting every row on each reload. Search no longer fails
    silently on very broad queries.
  - Arrow and j/k browsing no longer re-renders the whole list and window
    on each key press.
  - Inline-image mail, remote-image mail and height measurement no longer
    do heavy HTML work on the main thread.
  - Contact mining runs off the main thread. Background polling no longer
    re-fetches send-as identities or rewrites every label each minute, and
    unchanged messages and threads are no longer rewritten during sync.
  - Arrow and j/k browsing re-renders only the selection, not the list.
  - Bulk archive/trash/star/read on a multi-selection writes all rows in
    one transaction and sends at most four Gmail requests at a time per
    account.
  - Sync decodes and parses messages in parallel off the sync actors, and
    HTML stripping no longer recompiles its regexes per message.
  - The settings badge refresh, split-compose thread lookup and deep links
    no longer read the encrypted database on the main thread.
  - Opening a conversation no longer rebuilds the window toolbar. The
    rebuild was more than half of the main-thread work of each open.

## [0.5.0] - 2026-09-29

### Added
- **Message and Go menus.** Reply, Reply All, Forward, Archive, Trash,
  Star, Read/Unread, Snooze and Label are in the menu bar, and Go jumps to
  any mailbox or saved view. Help → Keyboard Shortcuts opens the list.
- **VoiceOver reads a thread row as one item** ("Unread. Alice. Subject.
  3 messages. Starred…") with Archive, Trash, Star and Snooze actions.
  Toasts and errors are announced; icon-only buttons have labels.
- **Empty lists say why.** First sync shows progress; Trash, Sent, Drafts,
  Starred and Snoozed have their own text; a filter that hides everything
  offers **Clear filters**.
- **Handle with Mish** — a wand button in the conversation toolbar opens
  Ask Mish, starts a fresh chat on the "Handle with Mish" model (Settings →
  AI; it follows the Ask Mish model until set), and asks the agent to work the
  open thread: look up related mail, draft the reply, or report that nothing is
  due. Sends still stop at the confirm card.
- **Model errors show the provider's message** — an HTTP 400/4xx from Claude,
  OpenAI-style, or Ollama endpoints now surfaces the server's own error text
  ("thinking.type: …", "messages.3.content: …") instead of the bare status.
- **Works on a plane.** Drafts saved without a network go to a local
  **Outbox** (sidebar) instead of failing, and upload to Gmail Drafts on
  reconnect; the compose footer reads "Saved offline". Archive, star,
  read/unread, snooze, labels, spam and trash made offline are queued and
  replayed before the next sync, so Gmail no longer reverts them. A Send
  that finds no network waits in **Scheduled** as "Waiting for connection"
  and goes out on reconnect instead of bouncing back into compose.

### Fixed
- **Sync no longer stalls on Gmail rate limits.** Requests are paced per
  account below Gmail's quota, a limited batch waits instead of exploding
  into single fetches, and history is committed in slices so one failure
  costs a slice, not the pass. A large delete in Gmail no longer blocks
  sync, and history that expired while offline reconciles cached labels
  and removes mail deleted meanwhile (Trash and Spam included).
- **Legacy mail bodies decode.** ISO-8859-1, Windows-1252, Shift_JIS and
  ISO-2022-JP messages no longer show as blank.
- **A send that timed out is not sent twice.** Each message carries a
  stable Message-ID, and a queued resend first checks Sent.
- **A rejected archive, trash or label edit reverts** instead of staying
  wrong locally.
- **Ask Mish errors are honest.** A provider error mid-stream or a stream
  that ends early shows an error, not a finished-looking answer; hitting
  the length limit or a refusal says so. Busy (429/529) and transient
  failures retry with backoff. Retry no longer duplicates your message.
- **Long threads keep their newest messages** in summaries and Ask Mish
  context; quoted trails are dropped and each message is labelled.
- **The Sync button appears only for sync errors.**
- **The pointing-hand cursor no longer sticks** after hover-archive.

### Security
- The Ask Mish confirm card shows the whole draft and makes hidden text
  visible (blank-line and space runs, zero-width, bidi, tag characters,
  combining floods). Every Ask Mish write needs a click, and create_draft
  warns about off-thread and Bcc recipients like send_draft.
- The update relauncher accepts only a UUID plan for the enclosing
  MishMail.app, and strips quarantine only from a bundle signed by its own
  Apple-anchored team. The updater checks the same Apple anchor.
- The MCP server has a read deadline, a connection cap and a constant-time
  token check; a huge number in a tool argument no longer crashes the app.
- One-click unsubscribe blocks numeric and IPv6 forms of private hosts.
- More risky attachment types (.terminal, .fileloc, .mobileconfig, .html,
  macro documents, …) ask before opening.
- Sender icons are drawn locally; sender domains no longer go to Google.
- Discarding a draft, removing an account or AI provider, blocking a
  sender, and deleting a view now ask first.
- **No more sticky "won't sync" banner offline.** Connectivity failures on
  any sync (background, manual, or the follow-up after a save or edit) now
  flip the sync control to "Offline · N to sync" with a passing notice on
  manual sync; the orange banner is reserved for errors that need you.
  Reachability is watched so queued work replays as soon as the network
  is back, not at the next poll.
- **A mailto: link no longer opens a second MishMail window.** Email links
  from other apps (browsers, Notion Calendar) now land in the window that is
  already open. A duplicate delivery of the same link within two seconds is
  ignored while its card is still up, so no second compose card is queued;
  re-clicking a link after dismissing the card still composes.

### Changed
- **Ask Mish costs less and reports cost fully.** Claude requests use
  prompt caching; Ask Mish turns now count toward Settings → AI spend,
  priced by the model actually used, including cache tokens. Opus 4/4.1
  prices are corrected. Thinking effort raises the output limit.
- **Text size** steps match the Settings picker and now apply to the
  compose body.
- **Ask Mish thinking works on hosted models.** The Think control is no
  longer local-only. Claude, GPT-5, Grok, Gemini, and OpenRouter models that
  can think send that effort on the wire (off / low / medium / high / extra
  high). Models that cannot think ignore it.
- **The model picker leads with models worth using.** Browse groups Frontier,
  Strong, and Current, and hides older ids such as Claude 3.5 Haiku and GPT-4o.
  A Show menu sets the floor (Frontier / Strong / Current / All). Search still
  finds the full list. Right-click a thinking model to set Ask Mish thinking.
- **MailStore command work is split out of the observable hub.** Sync,
  mutations, compose/drafts, reminders, AI triage, and account lifecycle live
  in `MailStore+…` files and Support policy types. The main class keeps UI
  state.
- **CI runs on every pull request and every push to main.** Unit tests and
  the app build are one job; the UI smoke suite is a separate job so a UI
  hang cannot hide unit-test results.
- **README privacy copy matches hosted AI.** Mail stays on this Mac except
  Gmail API traffic; a hosted model you assign can receive that task's mail
  text after host consent. Silent auto-sort still refuses cloud providers.
- **The unit-test target includes domain sources by directory.** New
  Gmail/Store/Auth/Support files no longer need a `project.yml` line. App-only
  files stay on an exclude list.
- **Ask Mish hides stale models in the picker.** Grok 4.2, Grok 2/3, image
  and non-reasoning ids, and Gemini 1.x/2.x no longer fill the browse list.
  Grok defaults to Grok 4.6. Gemini defaults to 3.7 Flash. A stored stale
  assignment (drafts, summaries, triage, Ask Mish) moves to that default.
  Search still finds the full list.
- **Compose From is a keyboard control.** ⇧Tab from To lands on the sending
  address. ↑↓ change it in place, Space or ↩ open the list, type a letter to
  jump, Esc closes the list without closing the draft. Rows show the display
  name, the mailbox it sends through, and a Default badge.
- **Ask Mish confirms show the draft body.** Create-draft and send-draft cards
  include a body preview. Return no longer confirms those actions. Send aborts
  if the draft changed after you confirmed.
- **Auto-sort stays on this Mac or the LAN.** If Triage is a cloud model,
  auto-sort skips so new-mail snippets are not uploaded. Ollama on a private
  LAN still runs. Settings says so.
- **Custom model hosts need a confirm.** A base URL that is not a shipped
  preset must be acknowledged in Settings before mail is sent there. Consent
  matches scheme, host, and port.
- **Long Ask Mish chats compact old tool results.** Later turns no longer
  resend every search and list payload. List tools keep a leading page.
- **mcp.json no longer stores the MCP bearer token.** The token stays in the
  Keychain. Helper scripts read it from `MISHMAIL_MCP_TOKEN` or
  `~/.config/mishmail/mcp-token`.

### Added
- **Moving from Notion Mail.** Settings lists a migration pane first: what
  to save before 22 Sep 2026, how drafts/scheduled mail stay in Gmail, and
  a JSON/CSV snippet importer that reads Notion exports (`shortcut`/`content`,
  `{ "snippets": […] }`, `{{First Name}}`). Cmd-K has “Moving from Notion
  Mail…”. README has the same steps.
- **Sign in with OpenRouter.** Settings → AI → Subscriptions can open a
  browser login and mint an API key for this app, the same PKCE flow Pi
  uses. You can still paste a key. The minted key stays in the Keychain.
- **Ask Mish shows its work.** Tool calls stream as live status rows you can
  expand (query, result, and clickable threads). Empty chats offer three
  starting prompts. After an answer, follow-up chips continue the turn. The
  open-thread chip names the subject. Local models get a Think control on the
  panel. Hosted chats get Fast vs Default. Confirm cards can open the draft
  in compose. Compose AI edits show a before/after strip with Keep and Undo.
- **⌘L copies a Gmail web link to the focused conversation**, Notion-style.
  The clipboard gets a `mail.google.com` URL that opens the conversation
  in the browser (with `authuser` so the right mailbox is selected). Also
  on the conversation ⋯ menu, the thread-list context menu, and in the
  command palette. Yields to typing in search, compose, and Settings;
  works while reading the conversation.
- **Unsubscribe from mailing lists, Gmail-style.** Messages that advertise
  RFC 2369 `List-Unsubscribe` show an Unsubscribe control next to From and in
  the ⋯ menu. After confirm, MishMail prefers RFC 8058 one-click HTTPS POST,
  then a mailto: send through Gmail, then the sender's unsubscribe page in
  the browser. Existing mail without stored headers is filled on open via a
  metadata fetch. Demo newsletters include sample headers.
- **⌘A selects every thread currently loaded in the list** — Gmail-style
  select-all for the existing checkbox multi-select, so the bulk-action bar
  (archive/trash/star/etc.) can act on the whole list at once instead of
  clicking or shift-clicking every row by hand. Only checks what's already
  loaded (the list is infinite-scroll); scrolling in more rows afterward
  doesn't retroactively check them. Never intercepts ⌘A where it already
  means "select all text" — search, compose, Settings, the selectable
  conversation text, and the message body itself all keep native
  select-all, so reading an email and hitting ⌘A still selects the email.

### Changed
- **From picker leads with the email.** Every linked identity used the same
  display name, so the menu was a wall of "Ron Boger — …" and hid the
  domain. Rows now start with the address, drop the name when it does not
  distinguish anyone, and only add "(via mailbox)" when the same address
  exists on another account. Duplicate addresses sort primary first. The
  open menu shows a checkmark on the current identity.

### Fixed
- **Google Gemini shows its mark in the model picker.** Matching uses the
  API host and OAuth vendor, not only the provider label.
- **Attachment chips open from a click anywhere on the chip, not only the
  filename.** Padding and the gray fill sat outside the Quick Look button,
  so clicks on the icon, size, or empty chrome did nothing. The whole chip
  is now the hit target. Eye and Save keep their own buttons.
- **↓ in Ask Mish no longer opens the next email.** Arrow keys first scroll
  the chat (or the conversation beside it). If there is nothing to scroll,
  they only move the list highlight. Enter still opens the thread.
- **Opening a thread from search could show the same image twice and hide
  the PDF.** A full re-fetch (CID inline / attachment recovery) fed the
  chip list parsed rows whose SQLite `id` was still nil. SwiftUI ForEach
  then treated every chip as one view. Chips now key off a stable part
  identity, and the re-fetch returns the inserted rows. Clicking a file
  chip Quick Looks it; Esc closes that preview instead of the thread.
- **Changing From after the first autosave still sent through the original
  mailbox.** New compose pins the Gmail API to the selected identity, not
  the autosave draft's account. The old pin made a From change (e.g. to
  berkeley after inserting `/bball`) send via the default mailbox, and
  Gmail rewrote From to that mailbox's default send-as address.
  Replies still stay on the thread's mailbox. Changing From also dirties
  the draft so the next save migrates it.
- **Multi-select `h`/`b` snooze only snoozed the last-focused thread, not
  the whole selection.** Every other bulk action (archive, trash, star,
  read/unread, spam) already checked the multi-select before falling back
  to the single focused thread; snooze never got that treatment. Picking a
  date now applies to every checked thread at once, with one combined
  undo toast.
- **Side-by-side compose opens every message in the conversation.** The
  reading pane still keeps one live body renderer (WebKit cost), but ⇧⌘↩
  expands all sent cards so you can read the full thread while drafting.
  Quoted trails stay behind each card's "…" pill. The conversation column
  is also hosted in a `NavigationStack` so the detail toolbar (exit split,
  archive/star, reply, ⋯ More) mounts again.
- **Switching mailboxes on a narrow window no longer dumps you into a
  conversation.** On windows below the three-pane width (~1080pt), clicking a
  sidebar mailbox could land with the top conversation auto-opened, replacing
  the list you asked for. Cause: a consumed-twice selection intent — when a
  SwiftUI selection-change fire found no pending intent it was treated as a
  click, and the "click" opened the quietly pre-highlighted top row. Unmatched
  fires are now treated as quiet (select only, never open). This is also what
  made the SidebarNav UI test fail on every CI run since it was added
  (issue #3) — the runner's window is 1000pt wide.
- **Thread list repaints no longer query the database per row** — building
  each row's right-click menu looked up the newest sender with a synchronous
  encrypted-SQLite query, and SwiftUI evaluates that menu for every visible
  row on every list update, so each repaint paid N queries on the main
  thread. The menu now reads the sender address already denormalized on the
  thread row. Label chips are also computed once per layout rebuild instead
  of re-allocated and re-sorted per row on every pass.
- **"Today" and "Yesterday" sections roll over at midnight** — date buckets
  and the Priority recency window captured "now" only when the list layout
  was rebuilt, so a list left open overnight kept yesterday's mail under
  "Today". The list now recomputes on day change (and time-zone changes),
  and the Labels view refreshes its section order when accounts are added
  or removed.

## [0.4.14] - 2026-08-02

### Added
- **MCP server** — an opt-in, in-process MCP endpoint (Streamable HTTP on
  127.0.0.1) so external AI agents can read and search threads, list and
  create drafts, write persisted per-thread AI summaries (shown in the
  reading pane with model attribution), and manage VIP senders (suggestions
  land in a "Suggested" group). Off by default; Settings → AI → MCP has the
  toggle, a fixed port (default 41888, 0 = random per launch), and copyable
  connect commands for Claude Code, Codex CLI, Gemini CLI, and any
  mcp-remote-capable client. Auth is a Keychain-held bearer token; a
  discovery file (mcp.json) is written next to the database while running.
  No send/archive/trash tools in this first version — drafts stay reviewable.

### Changed
- **Shift+I on an already-read conversation marks it unread** — Gmail's chord
  still marks unread threads read; when every focused or multi-selected
  conversation is already read, Shift+I flips them to unread instead of a
  no-op. Shift+U still always marks unread.

## [0.4.6] - 2026-07-27

### Fixed
- **The update restarts the app. The cause was never the sandbox.** Three
  releases shipped three different relaunch mechanisms, all failing with the
  same LaunchServices -10810, and the real reason was one the earlier fixes
  couldn't have addressed: **every file a sandboxed process writes is
  force-quarantined by the kernel, and the sandbox denies `removexattr` on
  `com.apple.quarantine`** — silently, since the call compiles and just
  returns -1. So the "clear quarantine" step added in 0.4.5 never cleared
  anything, the freshly installed update stayed quarantined, and macOS
  refuses to launch a quarantined bundle that isn't notarized. That includes
  the embedded relauncher, which is why it couldn't start.

  Two changes make it work. The relauncher is now signed **without** the
  sandbox entitlement, so it can actually strip the attribute; the app's
  entitlements are selected through a build variable rather than an
  xcodebuild command-line setting, which applied to every target and was how
  the helper silently inherited the sandbox. And MishMail starts the helper
  **before** the swap, from its own registered, unquarantined bundle — after
  the swap the only copy on disk is the update's, which cannot be launched
  until something unquarantines it.

  `make install` and `make release` now refuse to ship a sandboxed
  relauncher, since the failure is otherwise invisible until an update is
  attempted.

## [0.4.5] - 2026-07-27

### Fixed
- **The restart works — the real cause was quarantine, not the sandbox.**
  0.4.4's embedded relauncher failed to launch with LaunchServices -10810, the
  same error the two earlier attempts hit. It was never a sandbox restriction:
  `ditto` stamps `com.apple.quarantine` onto *every* file it extracts from the
  downloaded zip, and the update only cleared it from the bundle root. The
  embedded relauncher is an app bundle in its own right, so it stayed
  quarantined — and macOS refuses to launch a quarantined bundle that isn't
  notarized, which these builds never are. 33 items in a freshly updated
  0.4.4 were still tagged. Quarantine is now cleared across the whole bundle,
  which is what the earlier root-only version should always have done.

## [0.4.4] - 2026-07-27

### Fixed
- **The update restarts the app, verified end to end.** Two previous attempts
  failed on real hardware: asking LaunchServices for a second instance of the
  bundle we're running from returns -10810, and the sandbox blocks spawning a
  shell to do it instead. MishMail now embeds a tiny second app,
  `MishMailRelauncher`, at `Contents/Library/`. A separate bundle id makes it
  an ordinary "open another app", which the sandbox allows, and it waits for
  MishMail to disappear before reopening it — so nothing conflicts and nothing
  stale is resolved. It has no Dock icon and no UI.

  The helper is built with the app's entitlements and is therefore sandboxed,
  which mattered: a sandboxed process can't `kill(pid, 0)` another one, so the
  first version read "already gone" immediately, reopened MishMail while it
  was still running, and exited before the quit it was waiting for. Liveness
  is asked through `NSRunningApplication` instead.
- **The failure dialog can no longer strand the app.** If the restart does
  fail, MishMail comes to the front before showing the alert — it once sat
  unseen on another Space while the app hung behind it on a closed database —
  and a backstop exits the process if termination is blocked past five
  seconds. Everything is already flushed by then; staying on screen only
  misleads.

## [0.4.3] - 2026-07-27

### Fixed
- **The update actually restarts the app now.** Updating 0.4.1 → 0.4.2 through
  the app worked right up to the restart: the permission panel appeared, the
  grant stuck, and the swap landed — but LaunchServices refused the relaunch
  with "a miscellaneous error occurred" (-10810). Asking it for a second
  instance of our own bundle from inside that bundle doesn't work, and
  replacing the bundle first makes it worse, because the registration it has
  cached points at the copy that was just deleted. The relaunch is now handed
  to a detached shell that waits for the app to exit before opening it: by
  then nothing is running to conflict with, and opening by path re-reads the
  bundle that's actually there.
- **Updates are checked on every launch.** The launch check went through the
  same once-a-day gate as the background tick, and that timestamp lives in
  preferences which survive an update — so relaunching straight into a
  brand-new release surfaced nothing until you pressed Check for Updates by
  hand. A launch is rare and one request is cheap; the hourly tick still
  covers a window left open for days.

## [0.4.2] - 2026-07-27

The first release that existing installs can take through the new in-place
updater, and cut partly to exercise it end to end.

### Fixed
- **`scripts/update-mishmail.sh` no longer prints an `xattr` usage dump**
  mid-install. The recursive form it used doesn't exist on this macOS; the
  quarantine attribute Gatekeeper reads lives on the bundle root anyway, which
  is what the app's own `clearQuarantine` clears.

### Changed
- **`make release` refuses to run unless `HEAD` is exactly `origin/main` and
  the tree is clean.** `gh release create` tags the *remote's* main, not local
  HEAD, so cutting a release with the version bump unpushed publishes a
  correct zip under a tag whose source still carries the old version — which
  is what happened to v0.4.1 and cost a `--cleanup-tag` redo. One comparison
  catches unpushed, behind, diverged, and released-off-a-side-branch alike;
  the clean-tree half covers changes that would land in the zip but not the
  tag.

## [0.4.1] - 2026-07-27

### Changed
- **Updates install themselves** — "Update App" used to download the release
  zip, extract it into a temp folder, and open Finder on it so you could drag
  the app into Applications yourself, with a Gatekeeper warning waiting at the
  end because the verified bundle was still tagged as quarantined. It is now
  one button, **Install and Relaunch**: the same download and verification
  (SHA-256, nested code signature, Team ID continuity, notarization for
  Developer ID builds), then an atomic swap over the installed app and a
  restart. Because MishMail is sandboxed it cannot write its own install
  folder unaided, so the first update asks once for permission to that folder
  and remembers it as a security-scoped bookmark; every later update is a
  single click. The quarantine tag is gone from this path — the update has
  already cleared stronger checks than Gatekeeper applies to an Apple
  Development build, and keeping it would make macOS refuse to launch the
  update at all. A declined grant, a failed swap, or an app running from a
  temporary location still reveals the verified app in Finder, quarantined,
  exactly as before. If a draft is open, the restart asks first.
- **Updates are pinned to the version they claim to be** — signatures prove
  identity, not freshness, so anyone who took over the GitHub account could
  have republished an old, validly signed, vulnerable build under a higher tag
  and rolled the app backwards past every other check. The extracted bundle's
  `CFBundleShortVersionString` now has to match the release it was offered as.

### Added
- **`scripts/update-mishmail.sh`** — updates an existing install from the
  terminal, running the same checks the app does. Mainly for crossing *to*
  0.4.1: builds older than this tag every download as quarantined, and macOS
  refuses to launch a quarantined build that isn't notarized, so updating
  through the old in-app flow ends in a Finder drag and a trip through System
  Settings. Also a recovery path if an in-place update ever fails.

## [0.4.0] - 2026-07-27

### Fixed
- **Instant reading pane on delete-advance** — trashing a conversation took
  ~180 ms to show the next one. The payload was already cached; the cost was
  the `await` reaching it. `ThreadDetailRepository` is an actor, so every read
  costs a MainActor → actor → MainActor round-trip, and the return hop waits on
  the very SwiftUI work the delete just queued (measured: cache *hits* cost the
  same as misses, which ruled out the lookup). Payloads the prefetch already
  produced are now mirrored on the main actor, so the pane paints with no hop
  at all — `open.ready` went from 176–209 ms to 0.0–0.1 ms. `ThreadDetailView`
  also seeds its state at `init`: `.id(thread.id)` remounts it per
  conversation, so `@State` started empty and the pane painted blank for a
  frame before `.task` could run, however fast the data arrived.
- **Single-key shortcuts work while reading a conversation** — `g i`, `j`/`k`,
  `e`, and every other Gmail-style key went dead once focus landed on the
  message text, so a full-window conversation had no keyboard way back to the
  inbox. The key monitor stood down whenever the first responder was an
  `NSTextField`/`NSTextView` — but SwiftUI renders selectable `Text` as a
  *read-only* `NSTextField`, and a conversation is built out of them, so simply
  reading an email disarmed the shortcuts. It now stands down only for
  **editable** text (search, compose, the label-picker query), which is the
  case the check was actually for. Esc no longer wastes its first press
  blurring selectable text either.
- **`g i` (and other go-to shortcuts) leave full-window conversations** — in
  Superhuman-style open, same-mailbox go-to used to no-op and leave you stuck
  inside the thread; it now returns to the list like Esc / the back button
  (cross-mailbox go-to already did via the view switch).
- **Reading-pane cache survives triage** — the payload cache and neighbor
  prefetch were keyed on a global content version that `reloadThreads()` bumped
  on every call. Since trash/archive/star/mark-read each schedule a reload, one
  keystroke evicted all ten cached conversations — including the prev/next
  neighbors the prefetch had warmed 50 ms earlier — so rapid triage always
  landed on a cold payload and the prefetch's work was always discarded.
  Cache validity is now a per-thread `ThreadContentRevision` that only moves
  when a sync actually rewrites that thread's message rows; label-only
  mutations leave every cached body valid. The open pane likewise refreshes
  in place only when its *own* conversation changed, instead of on any DB
  activity anywhere.
- **Gmail Shift+I / Shift+U mark read/unread** — those chords were swallowed
  without effect (`charactersIgnoringModifiers` keeps Shift on letters). They
  now mark the focused (or multi-selected) conversation read / unread. Letter
  single-key shortcuts are also case-insensitive so Caps Lock no longer breaks
  them.

### Added
- **Full-window conversations (Superhuman-style, now the default)** — clicking
  a conversation (or pressing ↩) opens it across the whole window instead of a
  reading pane beside the list; Esc, `g i` (or any go-to), or the back button
  returns to the list. Settings → Appearance → "Opening a conversation"
  switches back to the reading-pane layout.
- **Sidebar on arrow keys** — ← hides the sidebar, → shows it (persisted, and
  now hidden by default). `/` still works with a hidden sidebar: it reveals
  the sidebar and focuses search.
- **Top row pre-selected** — on launch, when switching mailboxes, and when
  refocusing the app, the top conversation is highlighted automatically
  (without opening or marking it read), so ↩ opens it immediately — no
  priming ↑/↓ or click needed.
- **Side-by-side compose (⇧⌘↩)** — view a draft next to the conversation it
  answers. Any thread-bound compose (reply, forward, or a reopened reply
  draft) can expand to a full-window split: the source conversation fills the
  left column, the draft the right. Toggle with ⇧⌘↩, the split button in the
  compose header, or the toolbar exit control; Esc steps back to the previous
  inline/floating placement first, then closes the draft. The same composer
  instance moves between placements, so typed text is never lost.

### Changed
- **Instant triage handoff** — archive, trash, spam, and snooze now publish
  their row/count changes before encrypted-database and Gmail work, and replace
  the reading pane with the next conversation in the same update. Repeated
  actions share a serial persistence tail and one coalesced reconciliation
  instead of blocking the UI and fully reloading after every key press.
- **Faster conversation opening** — reading-pane headers, initial bodies, and
  attachments load off the main actor in one database snapshot. A bounded LRU
  retains actual neighbor payloads, so prefetch work is reused instead of
  discarded and message cards no longer query attachments while rendering.
- **Finder-speed keyboard browsing** — list focus lives on a dedicated
  `ListFocusState` (not a MailStore `@Published`), so holding ↓ / j no longer
  re-renders the reading pane, sidebar, or every thread row. The expensive
  `openedThreadId` still follows after a 150 ms settle (longer under load so
  key-repeat does not hydrate intermediate conversations). Neighbor header/body
  prefetch arms only when a conversation actually opens. Display-order moves
  use an O(1) id→index map. `ThreadRow` takes an equatable model (no
  `EnvironmentObject`) so unfocused rows skip body work on each repeat. The
  first keyboard selection still opens correctly in compact and three-pane
  layouts instead of requiring a priming click or Enter.
- **Lower HTML-mail idle memory** — MishMail retains one warm WebView instead
  of three, keeps only one sent message body expanded at a time, uses a smaller
  quote-analysis cache, builds the CSP fallback only when needed, and releases
  idle WebViews under macOS memory pressure.
- **Aligned participant headers** — compact and expanded message details use
  the same FROM/TO grid; bare addresses truncate in the middle and the
  disclosure chevron has a fixed optical frame.

### Fixed
- **Signing / demo hardening follow-ups** — the signing check only accepts
  certificates backing a currently valid identity (expired/revoked certs no
  longer count); `make release` notarizes and staples before publishing;
  `make run DEMO=0` refuses ad-hoc signing before building instead of after;
  UI-test fixture processes can no longer connect real accounts (same guard
  as the demo); the Settings Google API pane explains instead of silently
  dropping credentials in demo/UI-test processes; and "make default mail app"
  waits out the user-paced system confirmation before reporting failure.
- **Thread list clicks work again after the pre-select open fix** — the
  already-selected-row open affordance no longer mounts a permanent
  `contentShape` + gesture on every row (that hijacked `List` selection on
  macOS). Unselected rows select/open normally; the pre-highlighted top row
  still opens on click via a selected-only overlay.
- **Esc exits side-by-side compose while drafting** — ContentView owns an
  explicit Esc priority ladder (slash picker → command palette → search focus →
  exit split → save & close draft) that runs before the compose-typing
  passthrough, so Esc works with the body editor focused and never relies on
  local-monitor install order. Search focus blurs the sidebar field without
  closing a floating/inline draft; second Esc still saves & closes after
  leaving split.
- **Inline reply scroll no longer fights the thread** — opening Reply keeps a
  stable top `scrollPosition` and one-shot bottom-scrolls the reply target
  above the reserved compose card (re-sticks on late WKWebView growth, disarms
  if you scroll away via content-offset / trackpad). Dismiss restores the
  pre-compose position, including single-message threads via the subject
  scroll id. Pathologically short panes float compose instead of a zero-height
  dock.
- **Personal replies re-surface archived promo threads in Primary** — tab
  placement (`inPromotions` / `inSocial`) now follows the newest *INBOX-bearing*
  message instead of the union of every historical label. A human reply on an
  archived no-reply invite (which still carries `CATEGORY_PROMOTIONS`) returns
  the conversation to Primary instead of staying hidden under Promotions.
  Existing caches recompute on migration v27; optimistic label mutations no
  longer clobber tab flags from the labelIds union.
- **Clicking the pre-highlighted top row now opens it** — the auto-selected
  row produced no selection change, so the very first click in a mailbox did
  nothing. Rows now request an explicit open when the click lands on the
  already-selected thread. The quiet highlight also no longer counts as "a
  conversation is open" for narrow windows, which used to boot the
  reading-pane layout into the wrong column.
- **Inline reply no longer livelocks the app** — the reading pane's measured
  frame fed the inline composer's reserved bottom inset while being measured
  *inside* that inset, so at window heights under ~1050 pt the two values had
  no fixed point: layout oscillated ~50×/s, pegging the main thread and
  growing memory without bound the moment a reply opened. The pane is now
  measured outside the inset, and a UI regression test drives
  reply → side-by-side → back and fails on any recurrence.
- **Source rebuilds no longer trigger recurring Keychain prompts by default** —
  the fictional developer demo uses an isolated, non-secret database key and
  never touches Keychain. Real-inbox launch/install commands now refuse an
  unstable ad-hoc signature and point to Apple's free Personal Team signing
  path; no paid Developer Program membership is required for personal use.
- **Inline reply no longer springs the thread viewport upward** — composer
  motion is scoped to the card, the reading-pane inset changes without
  animation, and short panes continuously resize the card or fall back to a
  floating composer. Growing the pane restores inline presentation rather
  than leaving a sticky one-way demotion.
- **Draft cards disappear during Undo Send** — the Gmail draft remains safely
  available for Undo, but its thread card, banner, and Drafts-list row are
  suppressed until Undo, failure, or successful send resolves. A sibling
  draft in the same conversation keeps the Drafts-folder row visible.
- **Keychain access failures no longer masquerade as missing authorization** —
  locked or temporarily unavailable Keychain items remain retryable instead
  of marking the account for reauthorization. OAuth setup guidance now
  correctly explains Google Testing-mode's seven-day token lifetime. Database
  and OAuth-client secrets also fail closed instead of generating or sending
  replacement values after a transient read failure.
- **HTML mail no longer collapses when remote images are blocked** — blocked
  or failed `<img>` tags keep capped authored width/height (max 1200×2000) so
  table-based transactional layouts (e.g. 2FA) keep vertical structure under
  Ask policy; successful loads restore any author inline styles that were
  temporarily overridden (never wipe unrelated `style` props). Placeholders
  reflow proportionally to the reading-pane width on resize. Height tracking
  uses a ResizeObserver plus image load/error events instead of a fixed ~1.2s
  poll. Complete HTML documents keep author head styles; CSP/CSS are injected
  via an HTML-aware scanner that skips comments and raw-text elements and ends
  open tags only at unquoted `>` (so decoy `<!-- <head> -->` or
  `data-decoy=">"` cannot disable CSP). Ask-mode privacy is independently
  enforced by a WebKit content rule installed before navigation, with a trusted
  CSP wrapper as a fail-closed fallback. Fragments still wrap.
  Message cards gain a manual **Show plain text** control for the multipart
  alternative. Recycled WebViews tear down observers and script handlers.

### Added
- **Default email app** — Settings → General can make MishMail the system
  default for `mailto:` links (browsers and other apps open compose here).
  Registers the `mailto` URL scheme and prefills To/Cc/Bcc/subject/body.
  An expanded in-progress compose is not clobbered; the link opens when that
  draft is closed. Opening `.eml` / `message/rfc822` files is not supported yet.
- **Per-account snippet scope** — snippets default to all accounts; optionally
  limit a snippet to one or more mailboxes (Settings → Snippets editor, same
  per-account idea as Gmail filters). The compose `/` picker and Snippets
  panel only show snippets available for the current From account.
- **Draft saved status** — compose autosaves after you pause typing and shows
  Saving… / Draft saved in the footer (Notion Mail-style). Header ✕ / Esc still
  dismiss and keep the draft; the old footer "Close" label is gone. Send /
  Discard / undo-send use the live autosave draft id (no orphan Gmail drafts).
- **Inline reply** — Reply / Reply all / Continue draft for the open thread
  docks compose on the reading column so the conversation stays readable.
  New mail and Forward stay floating; **Pop out** promotes inline → card.
- **Thread focus (⌘↩)** — with a conversation selected (and compose not
  claiming Send), ⌘↩ fills the app with the reading pane. Esc exits focus.
  Toolbar: Focus Conversation. Documented on the `?` shortcuts sheet.

### Changed
- **Mark-as-read waits ~1s on open** — skimming the inbox with j/k or
  click-select no longer clears every unread badge on contact. Stay on a
  conversation for about a second (or press `u`) to mark read. **Archive
  (`e`) marks read immediately** so a quick archive does not leave the
  thread unread in All Mail.
- **Snippets settings list scrolls clearly** — list is height-constrained with
  always-visible scroll indicators and a “Scroll for more” fade when content
  overflows.
- **Design/AppIcon.svg** — source artwork updated to the MishMail apricot
  (no Perfect Mail checkmark badge). Shipping PNGs were already apricot.

### Changed
- **Taller inline reply compose** — card height 380→460; collapsed-quote body
  editor floor 120→180 so short replies get a real writing surface.

### Fixed
- **Message-card "…" hides plain `>` history** — quote collapse now treats a
  run of ≥2 `>`-prefixed lines to EOF (and peels a trailing `>` block above a
  later "On … wrote:") as the trail, so nested history without a bare
  attribution no longer stays always-visible. HTML without structured
  gmail_quote falls back to the plain-text head when collapsed. Heuristic
  tradeoff (documented in tests): multi-line trailing shell/docs snippets
  that look like `> cmd` collapse behind "…" too; single-line citations do not.
  CRLF bodies are normalized first (Swift treats `\r\n` as one Character).
- **Slash snippet picker ranking / stale rows** — `/bball` ranks exact and
  prefix name matches first, selection tracks snippet identity (not a recycled
  list index), and the picker re-scrolls when the query narrows so Enter and
  the highlighted row stay on the same snippet.
- **Snippet scope for removed accounts** — signed-out mailbox emails stay
  editable as removable “Removed account” rows (list shows a warning) so a
  solely-orphaned snippet isn’t stuck invisible with no UI path to fix it.
  Import reports unknown `accountIds` in the result string.
- **Delete under `is:unread` advances to the next thread** — opening an unread
  conversation pins it via read-state stickiness so the reading pane doesn't
  blank; trash/archive/spam now still remove the row optimistically so
  Gmail-style auto-advance lands on the next conversation instead of clearing
  selection. Undo under an unread filter re-pins the row so it reappears.
- **Keybinding overrides beat new defaults** — a stored rebind (e.g. archive →
  `x`) is not stolen by a newly added catalog default on the same key;
  colliding defaults are migrated onto a free key.
- **Collapsed quote height no longer leaves a dead gap** — HTML body measure
  uses visible child bottoms instead of `scrollHeight` (which often mirrored
  the WKWebView frame when content was shorter), so the "…" pill sits under
  the authored text.
- **Reply / reply-all / forward ignore draft messages everywhere** — shared
  `ForwardComposer.newestSentMessage` resolver used by keyboard `r`/`a`/`f`, the
  command palette, and the reading-pane toolbar (not toolbar-only).
- **Empty reply drafts no longer preview the quote trail** — quote-only bodies
  (reply opened, saved without typing) show the empty-draft state instead of
  dumping "On … wrote:" into the card.
- **Per-message Continue / Discard** — multi-draft threads edit/delete the card
  that was clicked, not always the newest draft in the thread.
- **Scroll-on-open anchors the newest sent message** — matches which card is
  expanded; drafts no longer steal the scroll position.
- **Date-section bucketing honors injected `now`** — `ThreadDateSections`
  no longer uses `Calendar.isDateInToday` / `isDateInYesterday` (wall clock),
  so pinned-time tests and any as-of grouping stay correct.
- **Send button no longer truncates to "Se…"** — the label is exempt from
  compression when the compose footer gets crowded.
- **Compose "Cancel" is now "Close"** — the button always saved your work as a
  draft (same as the header ✕); the label now says so. Trash remains the
  destructive discard.

### Changed
- **Schedule send uses the snooze picker** — the chevron next to Send opens
  the same natural-language date sheet as snoozing (type "tomorrow 9am",
  "mon", "aug 12", or pick a preset; fully keyboard-driven) instead of a menu
  plus calendar sheet. Past dates are filtered out.

### Added
- **Reply all button** — on multi-recipient messages (extra To/Cc beyond a
  plain reply), the reading pane shows Reply all next to Reply (toolbar,
  header icons, and message action bar). Keyboard `a` was already wired.
- **⌘↩ saves a snippet** — in Settings → Snippets create/edit, Cmd-Return
  saves (plain Return still inserts a newline in the body editor).
- **Multi-select** — `x` toggles a checkbox on the focused conversation
  (rebindable); row checkboxes (Notion-style, visible on hover or when any are
  selected); Shift-click a checkbox to select a range; bulk Archive / Trash /
  Star / Read-Unread / Spam via shortcut or the selection bar; Esc clears
  checks. Bulk mutations reload the list once.
- **Draft cards in the thread** — unsent Gmail drafts render as a dedicated
  card (orange "Draft" pill, "Not sent", left accent, compact authored
  preview without the quote trail). Continue / Discard sit on the card at the
  bottom of the conversation; a slim top banner offers Continue only on long
  threads (>3 messages) so short conversations aren't double-cued.

## [0.3.0] - 2026-07-11

### Added
- **Reading-pane ⋯ menu** — always multi-item: mark read/unread, snooze, mark
  as spam / not spam, block/unblock sender, open in Gmail (plus forward-all when
  multi-message). Spam shortcut `!` (rebindable in Settings → Keyboard shortcuts;
  toggles not-spam when already in Spam).
- **Matching Gmail filters under each message** — collapsible disclosure when a
  filter's criteria match; shared cache with Settings → Gmail filters. Best-effort
  local match (`OR`, unary `-term`, structured criteria).
- **Gmail web deep links** — `authuser=` with correct encoding (including `+` in
  addresses) for thread and filters-settings URLs.
- **Remote image policy** — Settings → Appearance: Ask each time (default),
  VIP senders, or Always. Load images click loads this message; the menu
  offers this conversation. Cleartext image URLs stay blocked either way.
- **Copy / Save thread as Markdown** — thread ⋯ menu: copy the conversation
  to the clipboard or save a `.md` file (bodies, Markdown links from HTML
  anchors, attachment filenames). Save failures alert and fall back to the
  clipboard.
- **Sponsorship** — README Support section, `.github/FUNDING.yml` (GitHub
  Sponsors + ETH), and a clickable "Support MishMail" line in the About panel.

### Notes
- **Report phishing** deliberately not shipped — no public Gmail API path; see
  `docs/plans/2026-07-11-report-phishing-deferred.md`.

### Fixed
- **Reply HTML matches Gmail** — untouched replies now send a multipart HTML
  alternative with a real `gmail_quote` / `gmail_attr` / nested `blockquote`
  and the original message's HTML inside (same pattern as forwards). Previously
  the plain `> ` quote trail was run through markdown, which flattened nested
  history, leaked literal `>` prefixes, and looked broken in Gmail and other
  clients. Quote matching uses a pinned date formatter; quoted HTML strips
  `cid:` images and document chrome (`style`/`html`/`head`) so the trail
  doesn't ship broken inline images or restyle the authored head. Scheduled
  sends hydrate the reply parent body (post-v24 off-row storage); reopened
  reply drafts recover the parent for In-Reply-To + HTML upgrade.
- **Own reply no longer bumps inbox position** — schema v25 adds
  `lastInboundDate` (nullable). Inbox / promotions / social / per-account
  inbox order by `COALESCE(lastInboundDate, lastDate)`; Sent, Drafts, search,
  and row timestamps keep `lastDate` = newest message. Date-section grouping
  ("Today" / "Yesterday" / …) uses the same activity key as the list sort, so
  a reply does not re-hoist a thread into "Today" under the default Group by
  Date view. "Remind if no reply" cancels only when `lastInboundDate`
  advances (own follow-ups on pure-outbound threads no longer clear the
  reminder).
- **Slash snippets mid-message** — caret-based detection so `/` works more
  than once and not only at the end of the body; settings rows open on click;
  safer programmatic body rewrites keep the caret in sync.

### Changed
- **Renamed to MishMail** — the app, bundle identifiers, Xcode project, targets,
  release artifacts, and GitHub repository references now use the MishMail name.
  The new bundle identifiers intentionally create fresh app containers and
  Keychain namespaces for this pre-1.0 rename.

### Also since 0.2.0
- **Compose markdown** — write `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``,
  `#`/`##`/`###` headings, lists, `>` quotes, and `$math$` / `$$display$$` in the
  compose body. Live syntax highlighting, footer format buttons, and shortcuts
  (⌘B / ⌘I / ⌘⇧X / ⌘E / ⌘⇧M / ⌘⌥1–3 / …). Source stays plain-text markdown
  (drafts, snippets, slash picker unchanged); send attaches an HTML alternative
  so recipients see the formatting. Math is lightly prettified for email (no
  full LaTeX engine).
- **Compose hyperlinks (⌘K)** — select text in the compose body and press
  ⌘K (or the link button in the footer) to insert a Gmail-style link. Links
  are stored as markdown `[label](url)` in the plain-text editor and converted
  to real `<a href>` anchors on send; bare `https://…` URLs are auto-linked
  too. Outside compose, ⌘K still opens the command palette.
- **Forward all** — thread ⋮ menu packages every message in the conversation
  into one Gmail-style forward body (oldest first). Still starts a **new**
  conversation (no `threadId` / `In-Reply-To`), matching gmail.com and Notion
  Mail. Single-message Forward (`f`, message actions) is unchanged.
- **Forward composer copy** — banner says “Starts a new conversation” so the
  source thread is not expected to absorb the send.
- **Richer forward HTML** — untouched forward packages (single or all) upgrade
  to multipart HTML using each part’s original markup; plain text prefers the
  HTML-derived body so it matches the reading pane. Forward-all is matched
  before single-message at send (suffix-order fix). Unsent DRAFT rows are
  excluded from Forward all so they never leak to recipients.
- **⌘K links a selected URL immediately** — with a `https://…` URL selected
  in the compose body, ⌘K links it directly instead of opening the link
  sheet.
- **Drag to reorder accounts** — drag an account row in the inbox switcher
  to reorder it; the order persists across restarts. With 2+ accounts, each
  row shows a grip and a “Drag to reorder” caption so the affordance is
  discoverable.

### Fixed
- **Dark-mode inline highlighter strips** — Word / Google Docs / some campus
  mail wrap body copy in `<span style="background:#fff">` (or similar). Those
  pure-inline light fills paint per-line white fragment boxes over the dark
  reading pane (black-on-white “highlighter” bars). Strip the fill on
  `display:inline` light surfaces (and attribute-matched `span`/`font`/… on
  first paint, excluding self-declared `inline-block`/`inline-flex` pills) so
  force-light text sits on the chrome; keep block cards and CTAs as real
  light surfaces with dark text. Inline-tag exclusion uses `:not(:where(…))`
  so JS fg classes keep source-order override for dark-on-dark nested sections.
- **Dark-mode HTML contrast from effective background** — force-light text
  over dark chrome, dark text only where the nearest opaque fill is light
  (Notion Calendar white canvas, cream panels, sig cards). Nested dark
  sections inside a white wrapper (Google welcome mail, blue CTAs) get light
  text again instead of dark-on-black. A `WKUserScript` at document-end stamps
  per-element fg classes from computed `background-color`; attribute selectors
  remain a self-only first-paint fast path. (Solid fills only — light
  `background-image` over transparent color is still a known gap.)
- **⌘K self-link trims stuck punctuation** — linking a selection like
  `(foo.com)`, `foo.com.`, or `foo.com,` now links the URL itself instead of
  producing a broken `https://(foo.com)`-style href. Balanced parens inside a
  path (`…/path(1)`) are kept, and parens in hrefs are percent-encoded so the
  markdown link re-parses cleanly.
- **Expired/revoked sign-ins now prompt reauthorization** — when Google
  rejects a stored refresh token (`invalid_grant`) or none is stored, the
  affected account shows a warning icon and a "Reauthorize…" button in
  Settings → Accounts instead of a raw token-exchange error.
- **New snippets now appear in compose immediately** — the `/` picker and
  Snippets panel pick up newly created snippets right away, without
  restarting the app.
- **Promotions/Social no longer show spam or archived mail** — lists and
  sidebar badges now match gmail.com (inbox + category, excluding SPAM and
  trash). Added denormalized `inSpam` (schema v19); mark-as-spam updates
  labels/denorm like the blocklist. Sidebar unread uses local denorm counts
  only (Gmail `CATEGORY_*` label totals include spam/archived and are not
  merged on top).

## [0.2.0] - 2026-07-09

### Security
- **OAuth loopback hardening** — 5-minute timeout tears down the catcher if
  sign-in is abandoned; only `/oauth2/callback` (and bare `/`) is accepted;
  wrong-state probes are ignored instead of aborting a legitimate flow.
- **HTML CSP tightened** — `base-uri 'none'`, explicit `form-action` /
  `frame-src` / `object-src 'none'`; remote images are HTTPS-only when enabled.
- **Update verification** — "Update App" downloads the release zip, verifies
  published **SHA-256** (`SHA256SUMS` from `make release`), code signature,
  **Team ID** continuity, and **notarization** for Developer ID builds, then
  reveals the app in Finder; failed checks open the GitHub release page.
- **Remote Ollama opt-in** — non-loopback endpoints need an explicit Settings
  toggle (and HTTPS) before mail content is sent.
- **Distribution entitlements** — `make release` / `make install` switch to
  `MishMail.Distribution.entitlements` (library validation on) when
  `Config/Local.xcconfig` sets `DEVELOPMENT_TEAM`.
- **Risky attachment prompt** — Open warns before launching app/script/installer
  filenames (still quarantined for Gatekeeper).

### Added
- **Slash-trigger snippets** — type `/` in the compose body (Notion Mail-style)
  to pop a snippet picker; keep typing to filter, ↑/↓ to choose, Return to
  insert, Esc to dismiss. `⌘/` toggles the snippets panel.
- **Single-brace snippet variables** — `{first_name}` now works alongside
  `{{first_name}}`, plus new variables: `{my_name}` / `{my_first_name}` (the
  sending account) and `{bcc_name}` / `{bcc_first_name}` / `{bcc_email}` (the
  person a move-to-Bcc snippet moved out of To).
- **Snippet editor upgrades** — `{variables}` highlight live as you type
  (accent for ones the app fills, orange for fill-in-yourself prompts like
  `{key_point_1}`), and typing `{` pops an autocomplete of every variable.
- **Snippet import** — Settings → Snippets → Import… reads a JSON file
  (`[{"name", "body", "movesToBcc"}]`), skipping names you already have —
  an easy landing pad for a Notion Mail snippet export.
- **Move-to-Bcc snippets** — a per-snippet toggle for intro etiquette:
  inserting the snippet moves To (the introducer) to Bcc and promotes Cc to
  To, so "Thanks {bcc_first_name} for the intro! Hi {first_name}, …" fills in
  both people correctly. Marked with a "→ Bcc" badge in snippet lists.
- **Formatted forwards** — forwarding now uses a Gmail-style
  "---------- Forwarded message ---------" block and, when the quoted text is
  left untouched, sends a `multipart/alternative` message that carries the
  original HTML formatting alongside the plain text. Editing inside the quote
  falls back to plain text so the two versions never disagree. The original's
  attachments come along too (shown as removable chips; Send waits until
  they've downloaded).
- **Forward focuses To** — pressing the forward shortcut opens compose with the
  cursor in the To field, ready to type a recipient.
- **Drafts keep their attachments** — closing compose (save-as-draft) now
  uploads the attached files with the draft, and reopening a draft brings its
  attachments back as chips, so nothing is silently dropped on a re-save.
- **Drafts keep HTML formatting** — a forward saved as a draft stores the
  original's HTML alongside the plain text (it looks right in Gmail too), and
  any draft re-saved or sent with an unedited body keeps its stored HTML —
  including rich drafts started in Gmail on the web.
- **On-device AI triage** — "Sort Inbox with AI" (Cmd-K) classifies threads into
  local buckets (Reply needed / FYI / Newsletter / Receipt / Other) via Ollama;
  results show as row tags, a new "AI category" grouping, and persist in their
  own table. Nothing leaves the machine.
- **AI thread summaries** — a streamed, local TL;DR on longer threads.
- **AI drafting** now streams token-by-token and works for new mail and
  forwards, not just replies.
- **Richer search operators** — `to:`, `subject:`, `is:unread`/`is:read`,
  `is:starred`, `after:`/`before:` (dates) join the existing `from:`, `label:`,
  `has:attachment`.
- **Lossless saved views** — "Save as view" now captures the full filter set
  (to/cc/bcc, subject, date window, calendar, exclude modes), not just the
  handful the form exposed.
- **Snippet variables** — `{{first_name}}`, `{{name}}`, `{{email}}`, `{{date}}`
  fill from the first recipient on insert.
- **Command palette v2** — fuzzy matching and context actions on the selected
  thread (archive, trash, star, snooze, reply, label).
- **First-run onboarding** — a guided Google-setup wizard with deep links to the
  exact console pages and drag-and-drop of the downloaded `client_secret.json`.
- **Sender avatars** in the thread list; **non-modal error banner** replacing the
  blocking alert; subtle list-row animations; a `PMTheme` design-token seed.

### Security
- WKWebView now uses a **default-deny navigation policy**: only the initial
  document load and user-clicked links are allowed. Meta-refresh, form
  submission, redirects, and iframe loads in crafted email can no longer reach
  the network (which had defeated remote-image/tracking-pixel blocking) or
  replace the message body with a phishing page.
- HTML email renders in an **ephemeral (non-persistent) web data store**.
- Downloaded/opened **attachments are tagged with `com.apple.quarantine`** and
  namespaced by message id (no filename collisions).
- Keychain items (refresh tokens, DB key) now pin
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — device-bound, excluded
  from backups/migration.
- Ollama: refuses to send message content to a non-loopback endpoint over plain
  HTTP.
- OAuth: surfaces Google's actual error (e.g. `access_denied`) instead of a
  generic "malformed redirect".
- **Hardened Runtime** is enabled (engages when signed with a real identity).
- **Per-view ephemeral WKWebView store** — HTML email views no longer share a
  single data store; each new view gets its own non-persistent store (JS still
  off), so remote-image cookies/cache cannot bleed across messages. Recycled
  views clear the DOM before re-use.

### Performance
- **Lazy message bodies** — the reading pane opens on headers only and hydrates
  a body when its card expands (last message always hydrated). AI summary still
  pulls full bodies for the whole thread.
- **Label-only Gmail history** — label add/remove on already-cached messages
  applies as a local delta (one write transaction per batch) instead of a full
  `getMessage` download; unknown local messages still full-fetch.
- **Thread denorm columns** (schema v16) — `inSent` / `inDrafts` /
  `inPromotions` / `inSocial` / `fromEmail` keep sidebar counts, mailbox
  filters, and VIP/blocklist short-circuits off the main-thread list path.
  VIP and blocklist still match *any* message From (denorm is a positive
  short-circuit only), so a reply cannot drop Priority or skip a block.
- **Parallel multi-account sync** — each account's `SyncEngine` runs in its own
  task; MainActor reloads (threads, blocklist, contacts) run once at the end.
- **FTS trim** (schema v17) — `message_fts` indexes subject + fromHeader only;
  body search falls back to server search. Prefix indexes kept.

### Packaging / open source
- Added `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`, this changelog, and a
  GitHub Actions CI workflow (build + test on `macos-14`).
- Signing moved to `Config/Signing.xcconfig` with a portable ad-hoc default and
  an optional git-ignored `Local.xcconfig` for a personal team — the repo now
  builds for anyone without an Apple Developer account.
- `.gitignore` covers `.claude/`, `DerivedData/`, `xcuserdata/`, and the local
  signing override.

## [0.1.0]
- Initial local-first Gmail client: multi-account sync, unified inbox, saved
  views & live filters, keyboard-first navigation, compose with drafts,
  scheduled/undo send, snooze, follow-up reminders, snippets, command palette,
  full-text search, SQLCipher-encrypted cache, and optional on-device AI
  drafting via Ollama.
