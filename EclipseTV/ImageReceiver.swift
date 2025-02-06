import MultipeerConnectivity
import SwiftUI

class ImageReceiver: NSObject, ObservableObject {
    private let serviceType = "eclipsecam" // Must match iOS app's serviceType
    private var peerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser

    @Published var receivedImage: UIImage?

    override init() {
        self.peerID = MCPeerID(displayName: "EclipseTV")
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)

        super.init()
        session.delegate = self
        advertiser.delegate = self

        print("📡 Apple TV is now advertising for connections...")
        advertiser.startAdvertisingPeer()
    }
}

// MARK: - MCSessionDelegate
extension ImageReceiver: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("🔄 Peer \(peerID.displayName) changed state to \(state.rawValue)")
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.receivedImage = image
                print("✅ Successfully received an image!")
            }
        } else {
            print("❌ Received data is not a valid image.")
        }
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension ImageReceiver: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("✅ Connection request received from \(peerID.displayName). Accepting...")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to start advertising: \(error.localizedDescription)")
    }
}
