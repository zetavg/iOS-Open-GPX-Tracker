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
@available(watchOS 10.0, *)
final class TrackingState: ObservableObject {
    static let shared = TrackingState()

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

    private init() {}

    /// Pull the latest track/waypoint data from the GPXSession model.
    func updateFromSession(_ session: GPXSession) {
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
    }
}
