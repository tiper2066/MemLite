import Darwin
import Foundation

@_silgen_name("MemLiteCopyOpenFilePaths")
private func MemLiteCopyOpenFilePaths() -> UnsafeMutablePointer<CChar>?

struct JunkRoots: Equatable {
    var trash: URL
    var caches: URL
    var logs: URL

    static var userHome: JunkRoots {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return JunkRoots(
            trash: home.appendingPathComponent(".Trash", isDirectory: true),
            caches: home.appendingPathComponent("Library/Caches", isDirectory: true),
            logs: home.appendingPathComponent("Library/Logs", isDirectory: true)
        )
    }
}

struct JunkScanResult: Equatable {
    let roots: JunkRoots
    let trash: [JunkFile]
    let caches: [JunkFile]
    let logs: [JunkFile]
    let directoriesToRemove: [URL]

    var trashBytes: UInt64 { trash.reduce(0) { $0 + $1.bytes } }
    var cacheBytes: UInt64 { caches.reduce(0) { $0 + $1.bytes } }
    var logBytes: UInt64 { logs.reduce(0) { $0 + $1.bytes } }
    var totalBytes: UInt64 { trashBytes + cacheBytes + logBytes }

    fileprivate var files: [JunkFile] { trash + caches + logs }
}

struct JunkFile: Equatable {
    let url: URL
    let bytes: UInt64
    fileprivate let kind: JunkLocation
}

enum JunkCleaner {
    static func scan(roots: JunkRoots = .userHome) -> JunkScanResult {
        let openPaths = pathsOpenByOtherProcesses()
        let trash = collect(root: roots.trash, kind: .trash, openPaths: openPaths)
        let caches = collect(root: roots.caches, kind: .caches, openPaths: openPaths)
        let logs = collect(root: roots.logs, kind: .logs, openPaths: openPaths)
        return JunkScanResult(
            roots: roots,
            trash: trash.files,
            caches: caches.files,
            logs: logs.files,
            directoriesToRemove: trash.directories + caches.directories
        )
    }

    static func delete(_ result: JunkScanResult) -> UInt64 {
        let openPaths = pathsOpenByOtherProcesses()
        var deletedBytes: UInt64 = 0
        for file in result.files where canDelete(file, roots: result.roots, openPaths: openPaths) {
            if unlink(file.url.path) == 0 {
                deletedBytes += file.bytes
            }
        }
        let directories = result.directoriesToRemove.sorted { $0.path.count > $1.path.count }
        for directory in directories where canRemoveDirectory(directory, roots: result.roots) {
            rmdir(directory.path)
        }
        return deletedBytes
    }

    static func confirmationText(for result: JunkScanResult) -> String {
        """
        휴지통  \(MemoryByteFormat.detail(result.trashBytes))
        사용자 캐시  \(MemoryByteFormat.detail(result.cacheBytes))
        사용자 로그  \(MemoryByteFormat.detail(result.logBytes))
        합계  \(MemoryByteFormat.detail(result.totalBytes))
        """
    }

    static func deletedText(bytes: UInt64) -> String {
        "\(MemoryByteFormat.detail(bytes))를 지웠습니다."
    }
}

private enum JunkLocation {
    case trash
    case caches
    case logs
}

private let protectedCacheNames: Set<String> = [
    "com.apple.akd",
    "com.apple.accountsd",
    "com.apple.applemediaservices",
    "com.apple.amsaccountsd",
    "com.apple.amsengagementd",
    "com.apple.identityservicesd",
    "com.apple.ids",
    "com.apple.security",
    "com.apple.protectedcloudstorage",
    "com.apple.trustevaluationagent",
    "cloudkit",
    "com.apple.bird",
    "com.apple.clouddocs",
    "com.apple.iclouddrivecore",
    "com.apple.homekit",
    "com.apple.mail",
    "com.apple.messages",
    "com.apple.imfoundation",
    "com.apple.imagent",
    "com.apple.photos",
    "com.apple.photolibraryd",
    "com.apple.music",
    "com.apple.itunes",
    "com.apple.itunescloudd",
    "com.apple.amplibraryagent",
    "com.apple.spotlight",
    "com.apple.fontregistry",
    "com.apple.ats",
    "com.apple.nsurlsessiond",
    "com.apple.nsurlstoraged",
    "com.apple.sharedfilelist",
    "com.apple.containermanagerd",
]

private let logExtensions: Set<String> = ["log", "asl", "crash", "ips", "spin", "diag", "hang"]

private func collect(
    root: URL,
    kind: JunkLocation,
    openPaths: Set<String>
) -> (files: [JunkFile], directories: [URL]) {
    guard let rootCanonical = canonicalPath(root.path) else {
        return ([], [])
    }
    var files: [JunkFile] = []
    var directories: [URL] = []
    walk(
        directory: root,
        rootCanonical: rootCanonical,
        kind: kind,
        isCacheRoot: kind == .caches,
        openPaths: openPaths,
        files: &files,
        directories: &directories
    )
    return (files, directories)
}

private func walk(
    directory: URL,
    rootCanonical: String,
    kind: JunkLocation,
    isCacheRoot: Bool,
    openPaths: Set<String>,
    files: inout [JunkFile],
    directories: inout [URL]
) {
    for name in directoryEntries(at: directory) {
        if isCacheRoot && isProtectedCacheName(name) {
            continue
        }
        let child = directory.appendingPathComponent(name)
        guard let info = linkStat(child) else { continue }
        let fileType = mode_t(info.st_mode) & S_IFMT
        if fileType == S_IFLNK {
            continue
        }
        guard let canonical = canonicalPath(child.path), isInside(canonical, root: rootCanonical) else {
            continue
        }
        if fileType == S_IFDIR {
            if kind != .logs {
                directories.append(child)
            }
            walk(
                directory: child,
                rootCanonical: rootCanonical,
                kind: kind,
                isCacheRoot: false,
                openPaths: openPaths,
                files: &files,
                directories: &directories
            )
            continue
        }
        guard fileType == S_IFREG else { continue }
        guard isDeletableFile(child, info: info, canonical: canonical, kind: kind, openPaths: openPaths) else {
            continue
        }
        let size = info.st_size > 0 ? UInt64(info.st_size) : 0
        files.append(JunkFile(url: child, bytes: size, kind: kind))
    }
}

private func isDeletableFile(
    _ url: URL,
    info: stat,
    canonical: String,
    kind: JunkLocation,
    openPaths: Set<String>
) -> Bool {
    if info.st_nlink > 1 {
        return false
    }
    if (info.st_flags & lockedFileFlags) != 0 {
        return false
    }
    if openPaths.contains(canonical) {
        return false
    }
    if isAliasFile(url) {
        return false
    }
    if kind == .logs && !isLogFile(url.lastPathComponent) {
        return false
    }
    return true
}

private func canDelete(_ file: JunkFile, roots: JunkRoots, openPaths: Set<String>) -> Bool {
    guard let info = linkStat(file.url) else { return false }
    let fileType = mode_t(info.st_mode) & S_IFMT
    guard fileType == S_IFREG else { return false }
    guard let canonical = canonicalPath(file.url.path) else { return false }
    guard let root = canonicalPath(rootURL(file.kind, roots: roots).path), isInside(canonical, root: root) else {
        return false
    }
    return isDeletableFile(file.url, info: info, canonical: canonical, kind: file.kind, openPaths: openPaths)
}

private func canRemoveDirectory(_ url: URL, roots: JunkRoots) -> Bool {
    guard let info = linkStat(url) else { return false }
    guard (mode_t(info.st_mode) & S_IFMT) == S_IFDIR else { return false }
    guard let canonical = canonicalPath(url.path) else { return false }
    for root in [roots.trash, roots.caches] {
        guard let rootCanonical = canonicalPath(root.path) else { continue }
        if canonical == rootCanonical {
            return false
        }
        if isInside(canonical, root: rootCanonical) {
            return true
        }
    }
    return false
}

private func rootURL(_ kind: JunkLocation, roots: JunkRoots) -> URL {
    switch kind {
    case .trash:
        return roots.trash
    case .caches:
        return roots.caches
    case .logs:
        return roots.logs
    }
}

private func isProtectedCacheName(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    if lowercased.hasPrefix("com.apple.icloud") || lowercased.hasPrefix("com.apple.mobileasset") {
        return true
    }
    return protectedCacheNames.contains(lowercased)
}

private func isLogFile(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    if lowercased.contains(".log") {
        return true
    }
    return logExtensions.contains((lowercased as NSString).pathExtension)
}

private func isAliasFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true
}

private var lockedFileFlags: UInt32 {
    UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE) | UInt32(UF_APPEND)
}

private func directoryEntries(at url: URL) -> [String] {
    guard let directory = url.path.withCString({ opendir($0) }) else {
        return []
    }
    defer { closedir(directory) }
    var names: [String] = []
    while let entry = readdir(directory) {
        let name = entryName(entry)
        if name != "." && name != ".." {
            names.append(name)
        }
    }
    return names
}

private func entryName(_ entry: UnsafeMutablePointer<dirent>) -> String {
    withUnsafePointer(to: entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
            String(cString: $0)
        }
    }
}

private func linkStat(_ url: URL) -> stat? {
    var info = stat()
    let result = url.path.withCString { lstat($0, &info) }
    return result == 0 ? info : nil
}

private func canonicalPath(_ path: String) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    return path.withCString { pointer in
        guard realpath(pointer, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
}

private func isInside(_ path: String, root: String) -> Bool {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return path.hasPrefix(prefix)
}

private func pathsOpenByOtherProcesses() -> Set<String> {
    guard let pointer = MemLiteCopyOpenFilePaths() else {
        return []
    }
    defer { free(pointer) }
    let blob = String(cString: pointer)
    var paths = Set<String>()
    for line in blob.split(separator: "\n") {
        guard let canonical = canonicalPath(String(line)) else { continue }
        paths.insert(canonical)
    }
    return paths
}
