# Eclipse App Store submission packet

Paste-ready answers for one universal-purchase record: iPhone/iPad
`com.mobleypro.eclipse.EclipseiPhone` and Apple TV
`com.mobleypro.eclipse.EclipseAppleTV`. Version 1.0.

Privacy policy: https://quest.eclipseapp.com/privacy

Support URL: https://quest.eclipseapp.com/support

The contact address on those pages is jonmobley@gmail.com. Change it in
`quest-relay/public/privacy.html` and `support.html` if that is not the public
support address, then redeploy.

## App Store text

Subtitle (30 characters): Present on the big screen

Description:

Eclipse is the operator’s remote for a show. Build a Show on iPhone or iPad,
then put it on an Apple TV, AirPlay, or HDMI display while the phone stays in
your hand.

Shows hold photos, videos, a screensaver, a live camera, websites, PDFs, and
countdowns. Present over AirPlay, or link the Eclipse Apple TV app on the same
Wi-Fi and send the library there. Ambient music can keep playing, and it can
pause when a video or website has sound.

Live Poll runs a poll or quiz on the big screen. Sign in with email, pick a
deck, and host from the phone. Remote albums load with a 6-digit code.

Keywords (99 characters):

show,presentation,apple tv,airplay,slideshow,poll,camera,screensaver,church,event

Promotional text:

Build a Show on your phone and present it on Apple TV, AirPlay, or HDMI.

## Age rating

Answer none for violence, sexual content, nudity, profanity, horror, alcohol,
tobacco, drugs, gambling, and contests.

Unrestricted web access: yes. Website cards accept any address the operator
types. That sets the rating to 17+.

Not made for kids.

## Privacy nutrition labels

Match the privacy manifests. Nothing is used for tracking.

Collected data, linked to the user, used for app functionality:

- Email address. Live Poll sign-in.
- Photos or videos. Shows and captures synced through the user’s iCloud.
- Other user content. Show details, saved website addresses, and remote-album
  codes sent to aircamtv.com.

Not collected: location, contacts, identifiers for advertising, purchase
history, browsing history, search history, audio data, health, financial info.

## Export compliance

Leave `ITSAppUsesNonExemptEncryption` set to false in both apps.

In App Store Connect, when asked:

- The app uses encryption. Yes.
- It is not limited to encryption inside Apple’s operating systems, because the
  iPhone app embeds WebRTC.
- It qualifies for the mass-market exemption: standard, publicly described
  encryption (HTTPS, DTLS, SRTP), and the app is not a cryptography product.

Annual self-classification (you send this; it is not filed from here):

Email a report to crypt@bis.doc.gov and enc@nsa.gov. State that Moxie LLC’s
Eclipse app for iOS and tvOS uses publicly available standard encryption
(TLS and WebRTC DTLS-SRTP) for authentication and content protection, that it
is mass-market software, and that it is not a cryptographic product. Include
the company name, the app name, and the date. Keep a copy. This is the usual
year-end report for the exemption; it is not legal advice.

## Review notes

Eclipse is a two-app system. Review the iPhone app and the Apple TV app
together.

Pairing: install Eclipse on Apple TV, open it, then on iPhone allow Local
Network and link that Apple TV from the connection control. Both devices must
be on the same Wi-Fi.

AirPlay: open a Show and present. The phone remains the controller. The
external display shows the Show.

Live Poll: sign in with the demo account below. Delete Account is on the deck
list (the screen titled Live Poll, after sign-in). The same action is Delete
account on https://quest.eclipseapp.com/host.

Demo Live Poll account: [email and a deck title — fill this in before submit]

NSAllowsArbitraryLoads is on so Phone Camera can reach hotspot addresses
outside private ranges (for example 192.0.0.2). Turning on
NSAllowsLocalNetworking would make iOS ignore the arbitrary-loads exception
and break that camera path.

The audio background mode is the ambient music player. It keeps playing when
the operator leaves the app. It is not a streaming service.

Camera and microphone: live camera on the external display, video recording,
and QR pairing.

## Screenshots still to capture

- iPhone 6.9 inch (iPhone 17 Pro Max class), portrait
- iPad 13 inch, landscape or portrait as the UI is designed
- Apple TV, 1920×1080

Suggested frames: Home with a Show, a Show grid, AirPlay or Apple TV present,
Live Poll host, Apple TV library.

## Archives

Build number `20260924.909` is stamped in both projects. Commit it before you upload.

An iPhone archive and an Apple TV archive were created:

- `~/Library/Developer/Xcode/Archives/2026-09-24/Eclipse iPhone 20260924.909.xcarchive`
- `~/Library/Developer/Xcode/Archives/2026-09-24/Eclipse Apple TV 20260924.909.xcarchive`

Both are signed with the Apple Development certificate (`get-task-allow` is true). App Store Connect will not accept them. Archive again from Xcode after an Apple Distribution certificate exists, then distribute with App Store Connect.

## What is not done from this Mac

- Deploy the CloudKit schema for iCloud.com.mobleypro.eclipse.EclipseiPhone to
  Production in the CloudKit dashboard.
- Create the App Store Connect record, attach the URLs above, and upload the
  archives. This Mac has an Apple Development certificate and a Developer ID
  certificate. An App Store upload needs an Apple Distribution certificate and
  an App Store Connect session.
- Send the BIS self-classification email.
- Capture the screenshots.
