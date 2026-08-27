import CoreGraphics
import Foundation

public struct CaptureDisplayGeometry: Equatable, Sendable {
    public let displayID: UInt32
    public let logicalX: Double
    public let logicalY: Double
    public let logicalWidth: Double
    public let logicalHeight: Double
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let rotationDegrees: Double

    public init(
        displayID: UInt32,
        logicalX: Double,
        logicalY: Double,
        logicalWidth: Double,
        logicalHeight: Double,
        pixelWidth: Int,
        pixelHeight: Int,
        rotationDegrees: Double
    ) {
        self.displayID = displayID
        self.logicalX = logicalX
        self.logicalY = logicalY
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.rotationDegrees = rotationDegrees
    }
}

public struct CapturePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PixelRect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// CGImage is immutable; this wrapper only transfers its retained reference.
public final class FrozenDisplayFrame: @unchecked Sendable {
    public let image: CGImage

    public init(image: CGImage) {
        self.image = image
    }
}

public struct FrozenCaptureDisplay: Sendable {
    public let geometry: CaptureDisplayGeometry
    public let frame: FrozenDisplayFrame

    public init(
        geometry: CaptureDisplayGeometry,
        frame: FrozenDisplayFrame
    ) {
        self.geometry = geometry
        self.frame = frame
    }
}

public struct CaptureDrag: Equatable, Sendable {
    public let displayID: UInt32
    public let start: CapturePoint
    public let current: CapturePoint
}

public struct SelectedCapture: Equatable, Sendable {
    public let displayID: UInt32
    public let pixelRect: PixelRect
    public let originalPNG: Data
}

public enum CaptureSelectionState: Equatable, Sendable {
    case selecting
    case cropping
    case completed
    case cancelled
    case noDisplaysAvailable
}

public enum CaptureSelectionError: Error, Equatable {
    case inactiveSession
    case displayUnavailable
    case selectionNotStarted
    case selectionTooSmall
    case displayGeometryChanged
}

public protocol CaptureImageCropping: Sendable {
    func cropPNG(
        frame: FrozenDisplayFrame,
        displayID: UInt32,
        pixelRect: PixelRect
    ) async throws -> Data
}

public actor CaptureSelectionSession {
    private var displays: [UInt32: FrozenCaptureDisplay]
    private let cropper: any CaptureImageCropping
    private var drag: CaptureDrag?
    public private(set) var state: CaptureSelectionState

    public init(
        displays: [FrozenCaptureDisplay],
        cropper: any CaptureImageCropping
    ) {
        self.displays = Dictionary(
            uniqueKeysWithValues: displays.map { ($0.geometry.displayID, $0) }
        )
        self.cropper = cropper
        state = displays.isEmpty ? .noDisplaysAvailable : .selecting
    }

    public var availableDisplayIDs: [UInt32] {
        displays.keys.sorted()
    }

    public var activeSelection: CaptureDrag? {
        drag
    }

    public func beginSelection(
        on displayID: UInt32,
        at point: CapturePoint
    ) throws {
        guard state == .selecting else {
            throw CaptureSelectionError.inactiveSession
        }
        guard let display = displays[displayID] else {
            throw CaptureSelectionError.displayUnavailable
        }
        let clamped = clamp(point, to: display.geometry)
        drag = CaptureDrag(
            displayID: displayID,
            start: clamped,
            current: clamped
        )
    }

    public func updateSelection(to point: CapturePoint) throws {
        guard state == .selecting else {
            throw CaptureSelectionError.inactiveSession
        }
        guard let drag,
              let display = displays[drag.displayID]
        else {
            throw CaptureSelectionError.selectionNotStarted
        }
        self.drag = CaptureDrag(
            displayID: drag.displayID,
            start: drag.start,
            current: clamp(point, to: display.geometry)
        )
    }

    public func finishSelection(
        currentGeometry: CaptureDisplayGeometry
    ) async throws -> SelectedCapture {
        guard state == .selecting else {
            throw CaptureSelectionError.inactiveSession
        }
        guard let drag,
              let display = displays[drag.displayID]
        else {
            throw CaptureSelectionError.selectionNotStarted
        }
        guard currentGeometry == display.geometry else {
            displays.removeValue(forKey: drag.displayID)
            self.drag = nil
            updateAvailabilityState()
            throw CaptureSelectionError.displayGeometryChanged
        }
        let rect = integralRect(
            from: drag.start,
            to: drag.current,
            geometry: display.geometry
        )
        guard rect.width >= 2, rect.height >= 2 else {
            self.drag = nil
            throw CaptureSelectionError.selectionTooSmall
        }

        state = .cropping
        let png: Data
        do {
            png = try await cropper.cropPNG(
                frame: display.frame,
                displayID: drag.displayID,
                pixelRect: rect
            )
        } catch {
            switch state {
            case .cancelled, .completed:
                throw CaptureSelectionError.inactiveSession
            case .noDisplaysAvailable:
                throw CaptureSelectionError.displayGeometryChanged
            case .cropping:
                guard displays[drag.displayID]?.geometry == currentGeometry else {
                    self.drag = nil
                    state = displays.isEmpty ? .noDisplaysAvailable : .selecting
                    throw CaptureSelectionError.displayGeometryChanged
                }
                state = .selecting
                throw error
            case .selecting:
                throw CaptureSelectionError.inactiveSession
            }
        }
        guard state == .cropping else {
            if state == .noDisplaysAvailable {
                throw CaptureSelectionError.displayGeometryChanged
            }
            throw CaptureSelectionError.inactiveSession
        }
        guard displays[drag.displayID]?.geometry == currentGeometry else {
            self.drag = nil
            state = displays.isEmpty ? .noDisplaysAvailable : .selecting
            throw CaptureSelectionError.displayGeometryChanged
        }
        let result = SelectedCapture(
            displayID: drag.displayID,
            pixelRect: rect,
            originalPNG: png
        )
        displays.removeAll()
        self.drag = nil
        state = .completed
        return result
    }

    @discardableResult
    public func applyCurrentDisplayGeometries(
        _ currentGeometries: [CaptureDisplayGeometry]
    ) -> [UInt32] {
        guard state == .selecting || state == .cropping else {
            return []
        }
        let currentByID = Dictionary(
            uniqueKeysWithValues: currentGeometries.map { ($0.displayID, $0) }
        )
        let invalidated = displays.compactMap { displayID, frozen -> UInt32? in
            guard currentByID[displayID] == frozen.geometry else {
                return displayID
            }
            return nil
        }.sorted()
        for displayID in invalidated {
            displays.removeValue(forKey: displayID)
            if drag?.displayID == displayID {
                drag = nil
            }
        }
        updateAvailabilityState()
        return invalidated
    }

    public func cancel() {
        guard state == .selecting || state == .cropping else {
            return
        }
        displays.removeAll()
        drag = nil
        state = .cancelled
    }

    private func clamp(
        _ point: CapturePoint,
        to geometry: CaptureDisplayGeometry
    ) -> CapturePoint {
        CapturePoint(
            x: min(max(point.x, 0), Double(geometry.pixelWidth)),
            y: min(max(point.y, 0), Double(geometry.pixelHeight))
        )
    }

    private func integralRect(
        from start: CapturePoint,
        to end: CapturePoint,
        geometry: CaptureDisplayGeometry
    ) -> PixelRect {
        let minX = max(0, Int(floor(min(start.x, end.x))))
        let minY = max(0, Int(floor(min(start.y, end.y))))
        let maxX = min(geometry.pixelWidth, Int(ceil(max(start.x, end.x))))
        let maxY = min(geometry.pixelHeight, Int(ceil(max(start.y, end.y))))
        return PixelRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    private func updateAvailabilityState() {
        if displays.isEmpty {
            state = .noDisplaysAvailable
        }
    }
}
