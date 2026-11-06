import Foundation

@main struct ChannelLogoResolverChecks {
    static func main() throws {
        let playlist = try String(contentsOfFile: "Sources/SofaTV/Resources/builtin_channels.txt", encoding: .utf8)
        let logoDirectory = "Assets/ChannelLogos"
        let availableResources = Set(try FileManager.default.contentsOfDirectory(atPath: logoDirectory)
            .filter { $0.lowercased().hasSuffix(".png") }
            .map { String($0.dropLast(4)) })
        let channelNames = playlist.components(separatedBy: .newlines).compactMap { line -> String? in
            guard line.hasPrefix("#EXTINF:"), let comma = line.firstIndex(of: ",") else { return nil }
            return String(line[line.index(after: comma)...])
        }
        let missing = Set(channelNames).filter { name in
            guard let resource = ChannelLogoResolver.resourceName(for: name, availableResources: availableResources) else { return true }
            return !FileManager.default.fileExists(atPath: "\(logoDirectory)/\(resource).png")
        }
        precondition(missing.isEmpty, "Missing bundled channel logos: \(missing.sorted())")
        precondition(ChannelLogoResolver.resourceName(for: "CCTV-5+ 体育赛事 高清") == "CCTV5+")
        precondition(ChannelLogoResolver.resourceName(for: "福建东南卫视 HD") == "东南卫视")
        precondition(ChannelLogoResolver.resourceName(for: "央视新闻频道") == "CCTV13")
        precondition(ChannelLogoResolver.resourceName(for: "凤凰卫视资讯台 高清", availableResources: availableResources) == "凤凰卫视资讯台")
        precondition(ChannelLogoResolver.resourceName(for: "一个自定义频道", availableResources: availableResources) == nil)
        print("Channel logo resolution passed for \(Set(channelNames).count) built-in channels and \(availableResources.count) bundled assets")
    }
}
