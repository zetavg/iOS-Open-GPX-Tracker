//
//  WatchSessionRecovery.swift
//  OpenGpxTracker-Watch Extension
//
//  Provides crash/force-quit recovery for the Watch app.
//
//  Uses an append-only JSONL journal to persist trackpoints and waypoints
//  incrementally, avoiding the O(n) full-GPX-export on every persist.
//  Each flush appends only new entries since the last flush,
//  keeping total I/O at O(T) instead of O(T²) over a session.
//

import Foundation
import CoreGPX
import CoreLocation

///
/// Handles persistence and recovery of the active tracking session on watchOS.
///
/// Trackpoints, waypoints, and segment breaks are buffered in memory and
/// periodically flushed (appended) to a JSONL journal file.  A small metadata
/// JSON is overwritten on each flush.  On launch, `InterfaceController` reads
/// the journal back to rebuild the session in a paused state.
///
class WatchSessionRecovery {

    // MARK: - Singleton

    /// Shared instance — holds the in-memory buffer between flushes.
    static let shared = WatchSessionRecovery()
    private init() {}

    // MARK: - In-Memory Buffer

    /// Journal entries accumulated since the last flush.
    private var pendingEntries: [JournalEntry] = []

    // MARK: - File Paths

    /// Directory used for recovery files (Library, not Documents, so they don't
    /// appear in the GPX file list).
    private static var recoveryDirectoryURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return library.appendingPathComponent("SessionRecovery", isDirectory: true)
    }

    /// The JSONL journal file (append-only).
    private static var journalFileURL: URL {
        return recoveryDirectoryURL.appendingPathComponent("_watchRecovery.jsonl")
    }

    /// JSON metadata (overwritten on each flush).
    private static var metadataFileURL: URL {
        return recoveryDirectoryURL.appendingPathComponent("_watchRecoveryMeta.json")
    }

    // MARK: - Journal Entry Model

    /// A single line in the JSONL journal.
    struct JournalEntry: Codable {
        /// Entry type: "T" = trackpoint, "S" = segment break, "W" = waypoint.
        let t: String
        var lat: Double?
        var lon: Double?
        var ele: Double?
        /// Unix timestamp (timeIntervalSince1970), trackpoints only.
        var ts: Double?
    }

    // MARK: - Metadata Model

    /// Lightweight metadata saved alongside the journal.
    struct RecoveryMetadata: Codable {
        /// The date/time when tracking was first started (nil if never started).
        var trackStartDate: Date?
        /// Elapsed stopwatch time in seconds at the moment of the last save.
        var elapsedTime: TimeInterval
        /// Whether tracking was active (true) or paused (false) when saved.
        var wasTracking: Bool
        /// The last GPX filename used for a user-initiated save (may be empty).
        var lastGpxFilename: String
        /// Whether the session had any waypoints.
        var hasWaypoints: Bool
    }

    // MARK: - Append (memory only, no I/O)

    /// Buffer a trackpoint. Called on every GPS update while tracking.
    func appendTrackPoint(_ location: CLLocation) {
        pendingEntries.append(JournalEntry(
            t: "T",
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            ele: location.altitude,
            ts: location.timestamp.timeIntervalSince1970
        ))
    }

    /// Buffer a segment break. Called when tracking is paused.
    func appendSegmentBreak() {
        pendingEntries.append(JournalEntry(t: "S"))
    }

    /// Buffer a waypoint. Called when the user drops a pin.
    func appendWaypoint(coordinate: CLLocationCoordinate2D, altitude: Double?) {
        pendingEntries.append(JournalEntry(
            t: "W",
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            ele: altitude
        ))
    }

    // MARK: - Flush (write pending entries to disk)

    /// Append all buffered entries to the journal file and overwrite metadata.
    ///
    /// - Parameter metadata: Current session metadata to persist.
    func flush(metadata: RecoveryMetadata) {
        let entries = pendingEntries

        let fm = FileManager.default

        // Ensure the recovery directory exists.
        if !fm.fileExists(atPath: Self.recoveryDirectoryURL.path) {
            try? fm.createDirectory(at: Self.recoveryDirectoryURL,
                                    withIntermediateDirectories: true,
                                    attributes: nil)
        }

        // 1. Append journal entries
        if !entries.isEmpty {
            let encoder = JSONEncoder()
            var data = Data()
            for entry in entries {
                if let line = try? encoder.encode(entry) {
                    data.append(line)
                    data.append(0x0A) // newline
                }
            }

            var writeOK = false
            if fm.fileExists(atPath: Self.journalFileURL.path) {
                // Append to existing file
                if let handle = try? FileHandle(forWritingTo: Self.journalFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                    writeOK = true
                }
            } else {
                // Create new file
                writeOK = ((try? data.write(to: Self.journalFileURL)) != nil)
            }

            // Only clear the buffer after a successful write to avoid data loss.
            if writeOK {
                pendingEntries = []
            }
        }

        // 2. Overwrite metadata (small, fixed size ~200 bytes)
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: Self.metadataFileURL, options: .atomic)
        }
    }

    // MARK: - Recover

    /// Recovered session data.
    struct RecoveredSession {
        let gpxRoot: GPXRoot
        let metadata: RecoveryMetadata
    }

    /// Attempts to load a previously persisted session from the JSONL journal.
    ///
    /// - Returns: A `RecoveredSession` if recovery files exist and contain data,
    ///            otherwise `nil`.
    static func recover() -> RecoveredSession? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: journalFileURL.path),
              fm.fileExists(atPath: metadataFileURL.path) else {
            return nil
        }

        // Parse metadata
        guard let metaData = try? Data(contentsOf: metadataFileURL),
              let meta = try? JSONDecoder().decode(RecoveryMetadata.self, from: metaData) else {
            print("WatchSessionRecovery:: failed to parse recovery metadata")
            clear()
            return nil
        }

        // Parse JSONL journal
        guard let journalData = try? Data(contentsOf: journalFileURL),
              let journalString = String(data: journalData, encoding: .utf8) else {
            print("WatchSessionRecovery:: failed to read journal file")
            clear()
            return nil
        }

        let decoder = JSONDecoder()
        let gpxRoot = GPXRoot(creator: kGPXCreatorString)
        let track = GPXTrack()
        var currentSegment = GPXTrackSegment()
        var hasContent = false

        for line in journalString.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(JournalEntry.self, from: lineData) else {
                continue // skip corrupted lines
            }

            switch entry.t {
            case "T":
                guard let lat = entry.lat, let lon = entry.lon else { continue }
                let pt = GPXTrackPoint(latitude: lat, longitude: lon)
                if let ele = entry.ele {
                    pt.elevation = ele
                }
                if let ts = entry.ts {
                    pt.time = Date(timeIntervalSince1970: ts)
                }
                currentSegment.add(trackpoint: pt)
                hasContent = true

            case "S":
                if currentSegment.points.count > 0 {
                    track.add(trackSegment: currentSegment)
                    currentSegment = GPXTrackSegment()
                }

            case "W":
                guard let lat = entry.lat, let lon = entry.lon else { continue }
                let wpt = GPXWaypoint(latitude: lat, longitude: lon)
                if let ele = entry.ele {
                    wpt.elevation = ele
                }
                gpxRoot.add(waypoint: wpt)
                hasContent = true

            default:
                continue
            }
        }

        // Finalize the last segment
        if currentSegment.points.count > 0 {
            track.add(trackSegment: currentSegment)
        }
        if track.segments.count > 0 {
            gpxRoot.add(track: track)
        }

        guard hasContent else {
            print("WatchSessionRecovery:: recovery journal is empty, ignoring")
            clear()
            return nil
        }

        return RecoveredSession(gpxRoot: gpxRoot, metadata: meta)
    }

    // MARK: - Clear

    /// Removes all recovery files and discards the memory buffer.
    /// Call after a successful user-Save or Reset.
    static func clear() {
        shared.pendingEntries = []
        let fm = FileManager.default
        try? fm.removeItem(at: journalFileURL)
        try? fm.removeItem(at: metadataFileURL)
    }

    /// Returns `true` if recovery data exists on disk.
    static var hasRecoveryData: Bool {
        return FileManager.default.fileExists(atPath: journalFileURL.path)
    }
}
