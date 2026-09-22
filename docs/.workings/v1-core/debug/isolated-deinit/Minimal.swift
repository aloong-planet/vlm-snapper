// Standalone diagnostic. Intentionally crashes on the affected runtime.
// Not a production source or acceptance test. See native-flake-diagnosis.md.
import Foundation

enum Context {
    @TaskLocal static var marker: Int = 0
}

@MainActor
final class Resource {
    #if NONISOLATED
    nonisolated deinit {}
    #else
    isolated deinit {}
    #endif
}

@MainActor
func releaseResource() {
    var resource: Resource? = Resource()
    weak var observer = resource
    withExtendedLifetime(resource) {}
    resource = nil
    precondition(observer == nil, "Resource must actually deallocate")
}

@MainActor
func runProbe() {
    let hasTask = withUnsafeCurrentTask { $0 != nil }
    FileHandle.standardError.write(Data("PROBE before release hasTask=\(hasTask)\n".utf8))
    #if NO_LOCAL
    releaseResource()
    #else
    Context.$marker.withValue(1) {
        releaseResource()
    }
    #endif
    FileHandle.standardError.write(Data("PROBE after release\n".utf8))
    exit(0)
}

@main
enum Probe {
    static func main() {
        DispatchQueue.main.async {
            #if IN_TASK
            Task { @MainActor in runProbe() }
            #else
            runProbe()
            #endif
        }
        dispatchMain()
    }
}
