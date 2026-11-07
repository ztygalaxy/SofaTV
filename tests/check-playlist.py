"""Exercise playlist parsing, source merging and deletions."""
from pathlib import Path
import subprocess

source = Path('Sources/SofaTV/ChannelCatalog.swift').read_text()
program = source + r'''

let first = try ChannelCatalog.parse("#EXTM3U\n#EXTINF:-1 group-title=\"TV\",One\nwebview://https://example.com/live\n#EXTINF:-1 group-title=\"TV\",One\nhttps://example.com/a.m3u8\n#EXTINF:-1 group-title=\"TV\",One\nhttps://example.com/a.m3u8")
precondition(first.count == 1 && first[0].sources.count == 2)

let second = try ChannelCatalog.parse("News,#genre#\nTwo,https://example.com/b.m3u8\nTV,#genre#\nOne,https://example.com/c.m3u8")
var fileList = ChannelList(id: "file:test", name: "Test", detail: "test.m3u", kind: .file, importedAt: Date(), channels: first)
let onlineList = ChannelList(id: "online:test", name: "Online", detail: "https://example.com/list", kind: .online, importedAt: Date(), channels: second)

var lists = [fileList, onlineList]
var merged = ChannelCatalog.merge(lists)
precondition(merged.count == 2 && merged[0].sources.count == 3 && merged[1].group == "News")

fileList.channels = ChannelCatalog.merge(first, into: fileList.channels)
precondition(fileList.channels.count == 1 && fileList.channels[0].sources.count == 2)

merged = ChannelCatalog.merge([onlineList])
precondition(merged.count == 2 && merged.first(where: { $0.name == "One" })?.sources.count == 1)

let one = ChannelCatalog.merge(lists).first(where: { $0.name == "One" })!
let scopedChannels = ChannelCatalog.deletingChannel(one, from: lists, inList: fileList.id)
precondition(scopedChannels[0].channels.isEmpty)
precondition(scopedChannels[1] == onlineList)
precondition(ChannelCatalog.merge(scopedChannels).first(where: { $0.name == "One" })?.url == URL(string: "https://example.com/c.m3u8"))
precondition(ChannelCatalog.deletingChannel(one, from: lists, inList: "missing") == lists)

let duplicateList = ChannelList(id: "duplicate", name: "Other source", detail: "", kind: .file, importedAt: Date(), channels: fileList.channels)
let scopedSources = ChannelCatalog.deletingSource(first[0].url, from: first[0], in: [fileList, duplicateList], inList: fileList.id)
precondition(scopedSources[0].channels[0].sources == [URL(string: "https://example.com/a.m3u8")!])
precondition(scopedSources[1] == duplicateList)
precondition(scopedSources[0].channels[0].identity == first[0].identity)
let removedLastSource = ChannelCatalog.deletingSource(scopedSources[0].channels[0].url, from: scopedSources[0].channels[0], in: scopedSources, inList: fileList.id)
precondition(removedLastSource[0].channels.isEmpty && removedLastSource[1] == duplicateList)
let sharedURL = Channel(name: "Different channel", group: first[0].group, url: first[0].url)
precondition(sharedURL.identity != first[0].identity)

lists = ChannelCatalog.deletingSource(URL(string: "https://example.com/c.m3u8")!, from: one, in: lists)
precondition(ChannelCatalog.merge(lists).first(where: { $0.name == "One" })?.sources.count == 2)

lists = ChannelCatalog.deletingChannel(one, from: lists)
precondition(ChannelCatalog.merge(lists).map(\.name) == ["Two"])
lists = ChannelCatalog.deletingGroup("News", from: lists)
precondition(ChannelCatalog.merge(lists).isEmpty)

let largeImport = (0..<10_000).map { index in
    Channel(name: "Channel \(index)", group: "Bulk", url: URL(string: "https://example.com/\(index).m3u8")!)
}
let mergedLargeImport = ChannelCatalog.merge(largeImport, into: [])
precondition(mergedLargeImport.count == 10_000)

let data = try JSONEncoder().encode([fileList, onlineList])
let restored = try JSONDecoder().decode([ChannelList].self, from: data)
precondition(restored == [fileList, onlineList])
print("Playlist checks passed")
'''
Path('/private/tmp/sofatv-parser-check.swift').write_text(program)
subprocess.run(['swift', '-module-cache-path', '/private/tmp/sofatv-clang', '/private/tmp/sofatv-parser-check.swift'], check=True)
