import Foundation
import VLMSnapperReleaseSupport

private func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 7, arguments[0] == "prepare" else {
    fail(
        "Usage: VLMSnapperSigningTool prepare <profile> <bundle-id> "
            + "<signing-identity> <base-entitlements> <output-entitlements> "
            + "<output-metadata>",
        status: 64
    )
}

do {
    try DeveloperIDProfilePreparation().prepare(
        profileURL: URL(fileURLWithPath: arguments[1]),
        bundleIdentifier: arguments[2],
        signingIdentity: arguments[3],
        baseEntitlementsURL: URL(fileURLWithPath: arguments[4]),
        outputEntitlementsURL: URL(fileURLWithPath: arguments[5]),
        outputMetadataURL: URL(fileURLWithPath: arguments[6])
    )
} catch {
    fail(error.localizedDescription)
}
