# Reply to App Review: Guidelines 4.3 and 4.2.6 (DRAFT)

Rejection of Eclipse 1.0 (iPhone/iPad, app id 6751125284). Apple asks us not to
resubmit but to reply in App Store Connect and answer nine questions.

Lines marked **[OWNER]** are things only you know. Check or replace them before
sending. Everything else is taken from the code, the build history and App Store
Connect.

---

## What the rejection means in plain words

Apple thinks Eclipse might be one of these:
- a copy of apps that already exist,
- a "me too" app in a crowded category, or
- an app made with an app-builder service for someone else.

They aren't saying something in the app is broken. They want proof that it's a
real, distinct product made by us.

The account itself probably counts against us. The team has 23 app records:
- Five other submissions were also rejected: PTZ Pilot, Glideshow Photos,
  Classy Studio, IQ Live Music and Eclipse itself.
- Several apps touch the same areas as Eclipse:
  - PTZ Pilot (PTZ camera control, sharing the same camera code),
  - Glideshow Photos (slideshows),
  - Videos: Video Library,
  - AirCam and EclipseCam (cameras),
  - EclipseTV (the Apple TV half of Eclipse, as a separate record).

Questions 5–7 are aimed at exactly this, so the answers have to be frank about it.

## Decisions for you (these change the answers)

1. **Apple TV app as its own record.** Today EclipseTV (com.mobleypro.eclipse.EclipseTV)
   is a separate app record. Apple often prefers one app that runs on iPhone, iPad and
   Apple TV under one purchase ("universal purchase"). Moving to that is a bigger
   change: the Apple TV app would have to join the iPhone record.
   - Recommended for now: keep them separate and explain it in Q5.
2. **Overlapping apps (decided 2026-11-13: Eclipse only).** PTZ Pilot and Glideshow
   Photos won't be released on their own, and the reply says so. Optional extra
   step: remove those two app records in App Store Connect (App Information >
   Remove App). This is allowed because neither was ever released. It can't be
   undone, so it's your click.
3. **How Eclipse was built.** Moxie LLC wrote it and owns it. No template or
   app-builder service was used. If you want to mention that AI coding assistants
   helped, that's your call. Guideline 4.2.6 is about template and app-generation
   services, not coding tools.

---

## Draft reply (paste into App Store Connect > Eclipse > 1.0 > App Review)

Hello, and thank you for the review. We believe Eclipse meets guidelines 4.3(a),
4.3(b) and 4.2.6. Our answers follow.

**1. What the app does and the problem it solves**

Eclipse runs the big screen at a live event from an iPhone or iPad. The operator
builds a "Show": an ordered set of photos, videos, websites, PDFs, slideshows,
countdown timers, a teleprompter, a live camera and audience polls. During the
event they fire each item to the screen with one tap.

The screen can be:
- an Apple TV running the Eclipse Apple TV app,
- any AirPlay receiver, or
- a display plugged into the iPhone or iPad.

The phone keeps its own controls and a preview. The audience sees only clean,
full-screen output, framed to the screen's real shape. That includes non-16:9 LED
walls, which the operator can describe with a custom screen size.

The problem it solves is running visuals at a small live event without a laptop,
a video switcher or a technician. Mirroring a phone shows the whole interface,
notifications and editing. Photo apps can't mix video, timers, web pages, cameras
and polls in a running order. Desktop presentation software needs a computer and
cables.

Eclipse adds features made for live work:
- A pre-built running order, with a "live" output kept separate from the operator's
  preview.
- Background music that pauses by itself when a video or website with sound comes up.
- Countdown and speaker timers.
- Show Live: a second iPhone or iPad on the same iCloud account can operate the same
  Show over the local network, for example a stage manager and a booth operator.
- Control of a network PTZ camera, with optional on-device voice commands.
- Audience polls (QuestPoll) shown on the big screen while people vote from their
  own phones.
- Pairing with Eclipse for Mac, to send the phone's camera into a Mac production.

**2. Intended users**

People who run screens at small and medium live events without a dedicated AV crew:
- church and community-hall volunteers,
- performers and emcees who carry their own screen content,
- school and corporate event organisers,
- small venues and conference rooms.

They are usually one person, sometimes two, operating from a phone or iPad near the
stage or at the back of the room, with an Apple TV or AirPlay screen already there.

Eclipse began as the tool our founder, a working performer and emcee, built to
run the screen at our own shows. Every feature has been used live on stage. We
now offer it to anyone in the same position: one person, a phone and a screen.

**3. The gap it fills**

Some existing apps mirror a phone to a TV, play a photo slideshow, or present
slides. None of them combine all of the following:
- a running order of mixed media,
- a clean output separate from the operator's preview,
- a choice between Apple TV, AirPlay or a wired screen,
- non-16:9 screen shapes,
- a second operator on another device,
- PTZ camera control, and
- live audience polling.

Professional presentation software that does more needs a computer, a capture
setup and training. Eclipse fits between "mirror my phone" and "hire an AV
company" for an operator with only a phone.

**4. Beta testing and feedback applied**

Eclipse has been in development since February 2025. It has gone through 42
TestFlight builds of the iPhone/iPad app. Our founder did the testing, at
rehearsals and at real shows. Each build was used in the same conditions the app
is made for, and the problems found there shaped the next build.

Examples of feedback that changed the production build:
- Venues with LED walls that aren't 16:9 asked for the picture to fit their screen.
  We added named custom screen sizes, and all output stages now frame to that shape.
- Operators sometimes sent a web page to the screen by accident while browsing their
  history. Opening a website no longer goes live; only "Send to TV" does.
- Music kept playing over videos with sound. Background audio now pauses for a video
  or website with sound and resumes afterwards.
- Poll hosts found the poll controls slow to use mid-event. The poll drawer now has a
  single large "Next" button, "+15s", a response count and a "Keep join QR up" option.
- Operators lost their place between events. The home screen now shows a "Continue"
  card for the last Show.
- Large libraries scrolled slowly. Thumbnails now load in the background, and
  imported files are moved instead of copied.

**5. Standalone or part of a suite**

Eclipse is one product that runs on three platforms, each with its own job:
- **Eclipse for iPhone and iPad** (this app): builds Shows and operates them. It is
  the controller and is required.
- **EclipseTV** (Apple TV, separate record): only receives and displays what the
  iPhone or iPad sends. It has no editing and no content of its own.
- **Eclipse Mac**: a desktop production app for multi-screen events that can take
  the iPhone camera and be driven by the iPhone remote.

Two earlier projects on our account overlapped with Eclipse: PTZ Pilot (a PTZ
camera remote) and Glideshow Photos (a photo slideshow). Neither was released, and
we will not release them as separate apps. Their useful parts, PTZ camera control
and slideshows, are now features inside Eclipse.

EclipseCam, an early camera experiment, will not be released either.

Our other apps are separate consumer products for different audiences. None of
them builds or runs a live show:
- Videos: Video Library: a personal video library ("Your videos, beautifully kept").
- AirCam: a shared event camera where guests' photos collect in one place
  ("Everyone's shots in one place").

**6. Could it be an add-on to another app?**

No. Eclipse is the core product, and its Apple TV and Mac companions depend on it.
None of our other apps runs a show, so there is nothing for it to be an add-on to.
We have already consolidated: PTZ camera control and photo slideshows were started
as separate apps (PTZ Pilot, Glideshow Photos). Both now live only inside Eclipse,
and those separate apps will not be released.

**7. Code shared with our other apps**

Eclipse shares these components with apps on our account:
- **CamTailKit**: the network PTZ camera control library. In Eclipse it drives the
  camera tile and voice control. It was first written for PTZ Pilot, which will not
  be released.
- **LivePollKit**: the client for our QuestPoll polling service. It is also used by
  Eclipse Mac. It signs the host in and runs the poll on the big screen.
- **EclipsePhoneCameraClient**: sends the iPhone camera to Eclipse Mac on the local
  network. It is also used by Eclipse Mac.
- **The display protocol** between Eclipse on iPhone and EclipseTV: the same product
  split across two devices.

All of these were written by us. The app's show model, running-order engine,
output framing, Show Live, editing interface and media library are unique to
Eclipse.

**8. Code shared with third-party apps**

None beyond standard third-party frameworks. The only third-party SDK is Sentry,
for crash reports. All features were written by our team.

**9. Made for a client?**

No. Moxie LLC wrote Eclipse and owns its concept, content and branding. It was not
built from a commercial template or an app-generation service, and it was not made
for a client.

Thank you for taking another look.

---

## After you send it

- I recommend sending the reply first, with no new build. Apple asked for answers,
  not a resubmission. If they accept, they'll say whether to submit again. The
  ready fixes on `fix/appstore-1-0-prep` (Show Live, local-network check, reviewer
  login and notes) then go out in a new build.
- If Apple holds to 4.3 after the reply, the realistic paths are:
  - (a) merge the Apple TV app into this one record as a universal purchase and
    stop shipping the overlapping standalone apps, or
  - (b) appeal to the App Review Board with the same answers.
