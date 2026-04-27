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
    private static let resourceBundleName = "KotoType_KotoType"

    static func load(bundle: Bundle? = nil) throws -> [ThirdPartyNotice] {
        let resolvedBundle = try resolvedBundle(explicitBundle: bundle)
        guard let url = resolvedBundle.url(forResource: manifestName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ThirdPartyNotice].self, from: data)
    }

    static func noticeText(for notice: ThirdPartyNotice, bundle: Bundle? = nil) throws -> String {
        let resolvedBundle = try resolvedBundle(explicitBundle: bundle)
        let resourceName = (notice.noticeFile as NSString).deletingPathExtension
        let resourceExtension = (notice.noticeFile as NSString).pathExtension
        guard let url = resolvedBundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func resourceBundle(
        bundleName: String = resourceBundleName,
        candidateBundles: [Bundle] = defaultCandidateBundles()
    ) -> Bundle? {
        let bundleFileName = "\(bundleName).bundle"

        for bundle in candidateBundles where bundle.bundleURL.lastPathComponent == bundleFileName {
            return bundle
        }

        for bundle in candidateBundles {
            for baseURL in [bundle.resourceURL, bundle.bundleURL].compactMap({ $0 }) {
                let candidateURL = baseURL.appendingPathComponent(bundleFileName)
                if let resolvedBundle = Bundle(url: candidateURL) {
                    return resolvedBundle
                }
            }
        }

        return nil
    }

    private static func resolvedBundle(explicitBundle: Bundle?) throws -> Bundle {
        if let explicitBundle {
            return explicitBundle
        }
        guard let resolvedBundle = resourceBundle() else {
#if SWIFT_PACKAGE
            let packageBundle = Bundle.module
            if packageBundle.url(forResource: manifestName, withExtension: "json") != nil {
                return packageBundle
            }
#endif
            throw CocoaError(.fileNoSuchFile)
        }
        return resolvedBundle
    }

    private static func defaultCandidateBundles() -> [Bundle] {
        var uniqueBundles: [Bundle] = []
        var seenPaths = Set<String>()
        for bundle in [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks {
            let path = bundle.bundleURL.resolvingSymlinksInPath().path
            if seenPaths.insert(path).inserted {
                uniqueBundles.append(bundle)
            }
        }
        return uniqueBundles
    }
}
