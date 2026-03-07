//
//  TrackingState.swift
//  OpenGpxTracker-Watch Extension
//
//  Bridges tracking data from WKInterfaceController to the SwiftUI map view.
//

import Foundation
import CoreLocation
import Combine

/// Observable state shared between InterfaceController and the SwiftUI map view.
///
/// Updates are gated behind ``isMapVisible``. When the map is not on screen,
/// incremental data (new track points, waypoints) is silently discarded and a
/// ``needsFullSync`` flag is set so the next `onAppear` triggers a complete
/// re-extraction.  This avoids all `@Published` churn (and the resulting SwiftUI
/// diffing / MapKit work) while the user is on the main WKInterface page.
@available(watchOS 10.0, *)
final class TrackingState: ObservableObject {
    static let shared = TrackingState()

    // MARK: - Visibility gate

    /// Set by WatchMapContentView's onAppear / onDisappear.
    var isMapVisible: Bool = false

    /// When `true`, the next time the map becomes visible a full
    /// sync from the GPXSession is required (e.g. after a reset, recovery,
    /// or because points were recorded while the map was hidden).
    var needsFullSync: Bool = true

    // MARK: - Location

    @Published var currentLocation: CLLocation?

    // MARK: - Track data

    /// Coordinate arrays for each completed track segment.
    @Published var completedSegments: [[CLLocationCoordinate2D]] = []
    /// Coordinates of the segment currently being recorded.
    @Published var currentSegmentCoordinates: [CLLocationCoordinate2D] = []
    /// Locations of all waypoints.
    @Published var waypointCoordinates: [CLLocationCoordinate2D] = []

    // MARK: - Display strings

    @Published var elapsedTimeString: String = "00:00"
    @Published var totalDistanceString: String = "0m"

    // MARK: - Actions (SwiftUI → InterfaceController)

    var addWaypointAction: (() -> Void)?

    /// Closure that performs a full sync from the current GPXSession.
    /// Set by InterfaceController on launch so the SwiftUI view can
    /// trigger a full re-extraction without coupling to InterfaceController.
    var performFullSync: (() -> Void)?

    /// Location stored while map is not visible, applied on next full sync.
    private var _silentLocation: CLLocation?
    /// Buffered display strings stored while map is not visible.
    private var _bufferedElapsed: String?
    private var _bufferedDistance: String?

    private init() {}

    // MARK: - Incremental updates (cheap O(1) operations)

    /// Append a single coordinate to the current (in-progress) segment.
    /// Only publishes when the map is visible; otherwise marks needsFullSync.
    func appendTrackPoint(_ coordinate: CLLocationCoordinate2D) {
        guard isMapVisible else {
            needsFullSync = true
            return
        }
        currentSegmentCoordinates.append(coordinate)
    }

    /// Append a waypoint coordinate.
    /// Only publishes when the map is visible; otherwise marks needsFullSync.
    func appendWaypoint(_ coordinate: CLLocationCoordinate2D) {
        guard isMapVisible else {
            needsFullSync = true
            return
        }
        waypointCoordinates.append(coordinate)
    }

    /// Promote the current segment into completedSegments and start a new empty one.
    /// Called when tracking is paused (new segment started).
    func finalizeCurrentSegment() {
        guard isMapVisible else {
            needsFullSync = true
            return
        }
        if !currentSegmentCoordinates.isEmpty {
            completedSegments.append(currentSegmentCoordinates)
            currentSegmentCoordinates = []
        }
    }

    /// Update the current location for camera tracking.
    /// Only publishes if the map is visible; otherwise stores silently for next appear.
    func updateLocation(_ location: CLLocation) {
        guard isMapVisible else {
            _silentLocation = location
            return
        }
        currentLocation = location
    }

    /// Update display strings. Only publishes when the map is visible.
    func updateDisplayStrings(elapsed: String? = nil, distance: String? = nil) {
        if let e = elapsed {
            guard isMapVisible else {
                _bufferedElapsed = e
                return
            }
            elapsedTimeString = e
        }
        if let d = distance {
            guard isMapVisible else {
                _bufferedDistance = d
                return
            }
            totalDistanceString = d
        }
    }

    // MARK: - Full sync (expensive O(n) — only on map open or reset)

    /// Pull the latest track/waypoint data from the GPXSession model.
    /// Only call this when the map becomes visible or after a reset/recovery while visible.
    func fullSyncFromSession(_ session: GPXSession) {
        var segments: [[CLLocationCoordinate2D]] = []

        // Segments from already-finished tracks
        for track in session.tracks {
            for segment in track.segments {
                let coords = segment.points.compactMap { pt -> CLLocationCoordinate2D? in
                    guard let lat = pt.latitude, let lon = pt.longitude else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                if !coords.isEmpty { segments.append(coords) }
            }
        }

        // Segments from finished segments in the current recording
        for segment in session.trackSegments {
            let coords = segment.points.compactMap { pt -> CLLocationCoordinate2D? in
                guard let lat = pt.latitude, let lon = pt.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            if !coords.isEmpty { segments.append(coords) }
        }

        completedSegments = segments

        // Active (in-progress) segment
        currentSegmentCoordinates = session.currentSegment.points.compactMap { pt -> CLLocationCoordinate2D? in
            guard let lat = pt.latitude, let lon = pt.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // Waypoints
        waypointCoordinates = session.waypoints.compactMap { wpt -> CLLocationCoordinate2D? in
            guard let lat = wpt.latitude, let lon = wpt.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // Apply any silently stored location
        if let loc = _silentLocation {
            currentLocation = loc
            _silentLocation = nil
        }

        // Apply any buffered display strings
        if let e = _bufferedElapsed {
            elapsedTimeString = e
            _bufferedElapsed = nil
        }
        if let d = _bufferedDistance {
            totalDistanceString = d
            _bufferedDistance = nil
        }

        needsFullSync = false
    }

    /// Clear all track data (called on reset).
    func clearAll() {
        completedSegments = []
        currentSegmentCoordinates = []
        waypointCoordinates = []
        _silentLocation = nil
        _bufferedElapsed = nil
        _bufferedDistance = nil
        needsFullSync = false
    }
}
