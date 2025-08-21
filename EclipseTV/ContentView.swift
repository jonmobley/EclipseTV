import SwiftUI

struct ContentView: View {
    @StateObject var imageReceiver = ImageReceiver() // Handles incoming images

    var body: some View {
        ZStack {
            if let image = imageReceiver.receivedImage {
                // Show received image, scaled proportionally to fill the screen
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea() // Extend to all screen edges
            } else {
                // Placeholder message when no image is received
                VStack {
                    Text("Waiting for Image...")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding()

                    Text("Ensure your iPhone is connected and sending images.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
    }
}
