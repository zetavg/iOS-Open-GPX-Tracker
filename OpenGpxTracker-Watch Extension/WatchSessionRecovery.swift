//
//  WatchSessionRecovery.swift
//  OpenGpxTracker-Watch Extension
//
//  Provides crash/force-quit recovery for the Watch app.
//
//  Persists the current GPX session to a recovery file after each
//  trackpoint or waypoint change, so data can be restored on next launch.
//

import Foundation
import CoreGPX

///
/// Handles persistence and recovery of the active tracking session on watchOS.
///
/// After every trackpoint or waypoint is added, the full session GPX is saved
/// to a recovery file alongside a small metadata JSON (elapsed time, tracking
/// status, etc.). On launch, `InterfaceController` checks for the recovery
/// file and restores the session in a paused state.
///
class WatchSessionRecovery {

    // MARK: - File Paths

    /// Directory used for recovery files (Library, not Documents, so they don't
    /// appear in the GPX file list).
    private static var recoveryDirectoryURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return library.appendingPathComponent("SessionRecovery", isDirectory: true)
    }

    /// The GPX recovery file.
    private static var recoveryGPXFileURL: URL {
        return recoveryDirectoryURL.appendingPathComponent("_watchRecovery.gpx")
    }

    /// JSON metadata for the recovery (elapsed time, status, etc.).
    private static var recoveryMetadataURL: URL {
        return recoveryDirectoryURL.appendingPathComponent("_watchRecoveryMeta.json")
    }

    // MARK: - Metadata Model

    /// Lightweight metadata saved alongside the GPX recovery file.
    struct RecoveryMetadata: Codable {
        /// Elapsed stopwatch time in seconds at the moment of the last save.
        var elapsedTime: TimeInterval
        /// Whether tracking was active (true) or paused (false) when saved.
        var wasTracking: Bool
        /// The last GPX filename used for a user-initiated save (may be empty).
        var lastGpxFilename: String
        /// Whether the session had any waypoints.
        var hasWaypoints: Bool
        /// Whether there were unsaved changes at the time of the persist.
        var hasUnsavedChanges: Bool

        /// Backward-compatible decoding: old recovery files without `hasUnsavedChanges`
        /// default to `true` (conservative — assume data is unsaved).
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
            wasTracking = try container.decode(Bool.self, forKey: .wasTracking)
            lastGpxFilename = try container.decode(String.self, forKey: .lastGpxFilename)
            hasWaypoints = try container.decode(Bool.self, forKey: .hasWaypoints)
            hasUnsavedChanges = try container.decodeIfPresent(Bool.self, forKey: .hasUnsavedChanges) ?? true
        }

        init(elapsedTime: TimeInterval, wasTracking: Bool, lastGpxFilename: String, hasWaypoints: Bool, hasUnsavedChanges: Bool) {
            self.elapsedTime = elapsedTime
            self.wasTracking = wasTracking
            self.lastGpxFilename = lastGpxFilename
            self.hasWaypoints = hasWaypoints
            self.hasUnsavedChanges = hasUnsavedChanges
        }
    }

    // MARK: - Save

    /// Persist the current session to the recovery files.
    ///
    /// Called after every trackpoint / waypoint addition to ensure data
    /// survives an unexpected termination.
    ///
    /// - Parameters:
    ///   - session: The current `GPXSession` (aliased as `GPXMapView` on watchOS).
    ///   - elapsedTime: Current stopwatch elapsed time in seconds.
    ///   - isTracking: Whether the app is currently in `.tracking` status.
    ///   - lastGpxFilename: The last saved GPX filename (may be empty).
    ///   - hasWaypoints: Whether the session contains waypoints.
    ///   - hasUnsavedChanges: Whether there are changes not yet saved to a GPX file.
    ///
    static func save(session: GPXSession,
                     elapsedTime: TimeInterval,
                     isTracking: Bool,
                     lastGpxFilename: String,
                     hasWaypoints: Bool,
                     hasUnsavedChanges: Bool) {

        // Ensure the recovery directory exists.
        let fm = FileManager.default
        if !fm.fileExists(atPath: recoveryDirectoryURL.path) {
            try? fm.createDirectory(at: recoveryDirectoryURL,
                                    withIntermediateDirectories: true,
                                    attributes: nil)
        }

        // 1. Save GPX
        let gpxString = session.exportToGPXString()
        try? gpxString.write(to: recoveryGPXFileURL,
                             atomically: true,
                             encoding: .utf8)

        // 2. Save metadata
        let meta = RecoveryMetadata(elapsedTime: elapsedTime,
                                    wasTracking: isTracking,
                                    lastGpxFilename: lastGpxFilename,
                                    hasWaypoints: hasWaypoints,
                                    hasUnsavedChanges: hasUnsavedChanges)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: recoveryMetadataURL, options: .atomic)
        }
    }

    // MARK: - Recover

    /// Recovered session data, if any.
    struct RecoveredSession {
        let gpxRoot: GPXRoot
        let metadata: RecoveryMetadata
    }

    /// Attempts to load a previously persisted session.
    ///
    /// - Returns: A `RecoveredSession` if recovery files exist and are valid,
    ///            otherwise `nil`.
    static func recover() -> RecoveredSession? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: recoveryGPXFileURL.path),
              fm.fileExists(atPath: recoveryMetadataURL.path) else {
            return nil
        }

        // Parse GPX
        guard let gpxRoot = GPXParser(withURL: recoveryGPXFileURL)?.parsedData() else {
            print("WatchSessionRecovery:: failed to parse recovery GPX")
            clear()
            return nil
        }

        // Parse metadata
        guard let metaData = try? Data(contentsOf: recoveryMetadataURL),
              let meta = try? JSONDecoder().decode(RecoveryMetadata.self, from: metaData) else {
            print("WatchSessionRecovery:: failed to parse recovery metadata")
            clear()
            return nil
        }

        // Only treat as a valid recovery if there is actual content.
        let hasTrackPoints = gpxRoot.tracks.contains { track in
            track.segments.contains { $0.points.count > 0 }
        }
        let hasWaypoints = gpxRoot.waypoints.count > 0

        guard hasTrackPoints || hasWaypoints else {
            print("WatchSessionRecovery:: recovery file is empty, ignoring")
            clear()
            return nil
        }

        return RecoveredSession(gpxRoot: gpxRoot, metadata: meta)
    }

    // MARK: - Clear

    /// Removes all recovery files. Call after a successful user-Save or Reset.
    static func clear() {
        let fm = FileManager.default
        try? fm.removeItem(at: recoveryGPXFileURL)
        try? fm.removeItem(at: recoveryMetadataURL)
    }

    /// Returns `true` if recovery data exists on disk.
    static var hasRecoveryData: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: recoveryGPXFileURL.path)
    }
}
