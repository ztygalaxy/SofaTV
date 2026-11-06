import Foundation

enum ChannelLogoResolver {
    private static let satelliteStations = [
        "内蒙古卫视", "黑龙江卫视", "东南卫视", "东方卫视", "北京卫视", "江苏卫视",
        "浙江卫视", "湖南卫视", "湖北卫视", "广东卫视", "广西卫视", "海南卫视",
        "重庆卫视", "深圳卫视", "四川卫视", "河南卫视", "贵州卫视", "江西卫视",
        "辽宁卫视", "安徽卫视", "河北卫视", "山东卫视", "天津卫视", "吉林卫视",
        "陕西卫视", "甘肃卫视", "宁夏卫视", "云南卫视", "山西卫视", "青海卫视",
        "西藏卫视", "新疆卫视"
    ]

    private static let cctvAliases: [(String, String)] = [
        ("央视体育赛事", "CCTV5+"), ("央视中文国际", "CCTV4"),
        ("央视国防军事", "CCTV7"), ("央视社会与法", "CCTV12"),
        ("央视奥林匹克", "CCTV16"), ("央视农业农村", "CCTV17"),
        ("央视综合", "CCTV1"), ("央视财经", "CCTV2"), ("央视综艺", "CCTV3"),
        ("央视体育", "CCTV5"), ("央视电影", "CCTV6"), ("央视电视剧", "CCTV8"),
        ("央视纪录", "CCTV9"), ("央视科教", "CCTV10"), ("央视戏曲", "CCTV11"),
        ("央视新闻", "CCTV13"), ("央视少儿", "CCTV14"), ("央视音乐", "CCTV15"),
        ("央视一套", "CCTV1"), ("央视二套", "CCTV2"), ("央视三套", "CCTV3"),
        ("央视四套", "CCTV4"), ("央视五套", "CCTV5"), ("央视六套", "CCTV6"),
        ("央视七套", "CCTV7"), ("央视八套", "CCTV8"), ("央视九套", "CCTV9"),
        ("央视十套", "CCTV10"), ("央视十一套", "CCTV11"), ("央视十二套", "CCTV12"),
        ("央视十三套", "CCTV13"), ("央视十四套", "CCTV14"),
        ("央视十五套", "CCTV15"), ("央视十六套", "CCTV16"), ("央视十七套", "CCTV17")
    ]

    static func resourceName(for channelName: String, availableResources: Set<String>? = nil) -> String? {
        let displayName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = displayName
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        var preferred: String?
        if compact.contains("CCTV") {
            if compact.contains("风云剧场") { preferred = "风云剧场" }
            else if compact.contains("第一剧场") { preferred = "第一剧场" }
            else if compact.contains("怀旧剧场") { preferred = "怀旧剧场" }
            else if compact.hasPrefix("CCTV4K") { preferred = "CCTV4K" }
            else if compact.hasPrefix("CCTV8K") { preferred = "CCTV8K" }
            else if compact.hasPrefix("CCTV4"), compact.contains("欧") { preferred = "CCTV4欧洲" }
            else if compact.hasPrefix("CCTV4"), compact.contains("美") { preferred = "CCTV4美洲" }
            let suffix = compact.dropFirst(4)
            let digits = suffix.prefix(while: \.isNumber)
            if preferred == nil, let number = Int(digits), (1...17).contains(number) {
                preferred = number == 5 && suffix.dropFirst(digits.count).hasPrefix("+") ? "CCTV5+" : "CCTV\(number)"
            }
        }

        if preferred == nil, compact.contains("CGTN") {
            if displayName.contains("法语") { preferred = "CGTN法语" }
            else if displayName.contains("俄语") { preferred = "CGTN俄语" }
            else if displayName.contains("阿拉伯") || displayName.contains("阿语") { preferred = "CGTN阿语" }
            else if displayName.contains("西班牙") || displayName.contains("西语") { preferred = "CGTN西语" }
            else if displayName.contains("纪录") || displayName.contains("记录") { preferred = "CGTN纪录" }
            else { preferred = "CGTN" }
        }

        if preferred == nil, compact.hasPrefix("CETV1") || displayName.contains("中国教育电视台1") { preferred = "CETV1" }
        if preferred == nil, let alias = cctvAliases.first(where: { displayName.contains($0.0) }) { preferred = alias.1 }
        if preferred == nil { preferred = satelliteStations.first(where: { displayName.contains($0) }) }

        guard let availableResources else { return preferred }
        if let preferred, availableResources.contains(preferred) { return preferred }
        if availableResources.contains(displayName) { return displayName }
        let key = normalizedKey(displayName)
        return availableResources
            .filter { normalizedKey($0) == key }
            .sorted { lhs, rhs in lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count }
            .first
    }

    static func normalizedKey(_ value: String) -> String {
        var result = value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_Hans_CN")).uppercased()
        for token in ["超高清", "高清", "频道", "电视台", "標清", "标清", "HD", "SD"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        result = result.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        if result.hasSuffix("台") { result.removeLast() }
        return result
    }
}
