import Foundation

enum MediaDisplayMode: String, CaseIterable, Codable {
    case inline = "Inline"
    case linksOnly = "Links Only"
}

enum SummaryStyle: String, CaseIterable, Codable {
    case thematic = "Thematic"
    case bullet = "Bullet"
}

struct AppSettings: Codable {
    var mediaDisplayMode: MediaDisplayMode = .inline
    var summaryStyle: SummaryStyle = .thematic
}
