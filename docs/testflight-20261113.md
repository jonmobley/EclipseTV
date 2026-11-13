# Eclipse build 2026111301 (iPhone and iPad only)

Built from EclipseTV branch release/testflight-20261113: feature/airplay-custom-screen-size at
8511a24 merged with main 8e5f149 (merges 4dedaf9, 741f573). Everything in 2026110801 (main 9ca1a63) is
kept. New since 2026110801:

- Screen Size (Settings → Display Mode): save named width×height shapes for a screen that is
  not 16:9, such as an LED wall. In Landscape the AirPlay picture is fitted to that shape with
  black around it, and the phone's camera, website, prompter and countdown stages frame
  content the same way; Fit/Fill and Reframe measure against it. Vertical ignores it (the
  choice is kept). Video re-crop still targets the plain 16:9 / 9:16 library shape. Swipe a
  size to delete, tap ⓘ to edit.
- From main, PR #86 (Phase 1 fixes): adding or opening a website from History never takes
  output live, Send to TV is the explicit go-live and works over a live still; Recents keep
  this phone's last-opened time ("Opened 3hrs ago"); downloading iCloud items say
  "Downloading…"; poll sign-in resumes the tapped poll and re-prompts when the server rejects a
  saved sign-in; Camera Live preview restarts after the AirPlay camera ends with a sheet open;
  a docked ribbon no longer resets the Show grid scroll; Search focuses on first tap;
  slideshow Edit mode's red minus removes the slide; jumping ahead in a poll no longer asks.
- From main, PR #87 (Phase 2 speed): grid thumbnails load four at a time with video posters on
  their own queue; adding a picked file moves instead of copying; batch import encodes
  thumbnails off the main thread; tap-to-preview repaints at once and the crossfade starts
  immediately.
- From main, PR #90 (Phase 3 UI): Home shows a Continue card for the last Show (or "Create your
  first Show"); Settings → Apple TVs says Connected only for the TV connected now; iPhone
  landscape website card and button column are centred, New Tab and Auto Scroll live in ⋯;
  slideshow editor edits the name in place, each slide has a thumbnail, name and its own
  Fit/Fill, drag to reorder, swipe to remove (one-time migration of Fill slideshows); poll
  drawer has a counts row, big +15s and one Next button; PTZ tile and hero show the camera's
  state instead of black and a tap with no camera opens setup.
- From main, PR #89 (Poll): the drawer's ⋯ menu gains Show Timer, Keep Join QR Up and Time per
  Question; "Manage on QuestPoll" opens the website signed in via a one-time link (plain page
  if the request fails).

Sibling packages: eclipsepro main 8dd92423 (LivePollKit with `setDisplay` / `webSignInLink`,
EclipsePhoneCameraClient), ahead of the fedfcff6 shipped in 2026110403. PTZ camera is CamTail
main ac076aa (CamTailKit 1.8.0: clearer camera states, permission lead-in, rides out blips),
which contains everything from the remove-joystick commit shipped in 2026110403. No Apple TV
build; the TV app is unchanged.

Owner steps before relying on this build's poll features: the QuestPoll server needs a deploy
with migration 0005 for the signed-in "Manage on QuestPoll" link and the screen options
(the app falls back to the plain page / existing behaviour until then).
