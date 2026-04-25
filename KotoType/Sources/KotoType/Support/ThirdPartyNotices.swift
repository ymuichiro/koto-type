import Foundation

struct ThirdPartyNotice: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let licenseName: String
    let projectURL: String
    let noticeFile: String
    let summary: String?
    let bundledComponent: String?
    let upstreamBaseModel: String?
    let revision: String?
}

enum ThirdPartyNoticesLoader {
    private static let manifestName = "ThirdPartyNotices"

    static func load(bundle: Bundle = .module) throws -> [ThirdPartyNotice] {
        guard let url = bundle.url(forResource: manifestName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ThirdPartyNotice].self, from: data)
    }

    static func noticeText(for notice: ThirdPartyNotice, bundle: Bundle = .module) throws -> String {
        let resourceName = (notice.noticeFile as NSString).deletingPathExtension
        let resourceExtension = (notice.noticeFile as NSString).pathExtension
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
