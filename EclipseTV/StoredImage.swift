import SwiftUI

struct StoredImage: Identifiable, Codable {
    let id: UUID
    let imageName: String
    let date: Date
    
    init(imageName: String) {
        self.id = UUID()
        self.imageName = imageName
        self.date = Date()
    }
}
