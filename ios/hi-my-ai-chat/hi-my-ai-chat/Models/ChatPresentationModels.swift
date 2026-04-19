import Foundation
import UIKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case chat
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "聊天"
        case .favorites:
            return "收藏"
        }
    }

    var systemImage: String {
        switch self {
        case .chat:
            return "message"
        case .favorites:
            return "bookmark"
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    enum State {
        case streaming
        case complete
        case failed
    }

    let id: UUID
    let role: Role
    var text: String
    var attachments: [ChatImageAttachment]
    var showsActions: Bool
    var state: State
    var favoritedAt: Date?

    var isFavorite: Bool {
        favoritedAt != nil
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        attachments: [ChatImageAttachment] = [],
        showsActions: Bool,
        state: State = .complete,
        favoritedAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.showsActions = showsActions
        self.state = state
        self.favoritedAt = favoritedAt
    }
}

struct ChatImageAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let data: Data
    let mimeType: String

    init(
        id: UUID = UUID(),
        data: Data,
        mimeType: String = "image/jpeg"
    ) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
    }

    var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    var image: UIImage? {
        UIImage(data: data)
    }

    static func make(from image: UIImage, maxDimension: CGFloat = 1_600) -> ChatImageAttachment? {
        let normalizedImage = image.normalizedForAttachment(maxDimension: maxDimension)
        guard let data = normalizedImage.jpegData(compressionQuality: 0.82) else {
            return nil
        }

        return ChatImageAttachment(data: data)
    }
}

struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let prompt: String
}

struct AttachmentAction: Identifiable {
    enum Source {
        case camera
        case photoLibrary
    }

    let id = UUID()
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let source: Source
}

struct FavoritedMessageEntry: Identifiable {
    let sessionID: UUID
    let sessionTitle: String
    let message: ChatMessage

    var id: UUID {
        message.id
    }

    var favoritedAt: Date {
        message.favoritedAt ?? .distantPast
    }
}

private extension UIImage {
    func normalizedForAttachment(maxDimension: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let size = self.size
        let longestEdge = max(size.width, size.height)
        let scaleRatio = longestEdge > maxDimension ? maxDimension / longestEdge : 1
        let targetSize = CGSize(
            width: max(size.width * scaleRatio, 1),
            height: max(size.height * scaleRatio, 1)
        )

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
