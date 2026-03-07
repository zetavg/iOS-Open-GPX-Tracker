//
//  WatchMapContentView.swift
//  OpenGpxTracker-Watch Extension
//
//  SwiftUI map view for Apple Watch showing tracks, waypoints, and user location.
//

import SwiftUI
import MapKit
import CoreLocation
import WatchKit

@available(watchOS 10.0, *)
struct WatchMapContentView: View {
    @ObservedObject private var state = TrackingState.shared

    // MARK: - Camera state

    @State private var position: MapCameraPosition = .automatic
    @State private var followUser: Bool = true
    @State private var cameraDistance: CLLocationDistance = 500
    /// Guards against treating a programmatic camera move as a user pan.
    @State private var isProgrammaticMove: Bool = false
    /// Work item for the pending programmatic-move reset, so overlapping
    /// location updates don't create cascading timers.
    @State private var programmaticMoveResetWork: DispatchWorkItem?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                ForEach(Array(state.completedSegments.enumerated()), id: \.offset) { _, coords in
                    if coords.count >= 2 {
                        MapPolyline(coordinates: coords)
                            .stroke(.blue, lineWidth: 3)
                    }
                }
                if state.currentSegmentCoordinates.count >= 2 {
                    MapPolyline(coordinates: state.currentSegmentCoordinates)
                        .stroke(.cyan, lineWidth: 3)
                }
                ForEach(Array(state.waypointCoordinates.enumerated()), id: \.offset) { _, coord in
                    Annotation("", coordinate: coord) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                    }
                }
                UserAnnotation()
            }
            .tint(.blue)
            .mapStyle(.standard)
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(.container, edges: .all)
            .overlay(alignment: .top) {
                HStack(spacing: 3) {
                    Text(state.elapsedTimeString)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text(state.totalDistanceString)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, -20)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraDistance = context.camera.distance
                if !isProgrammaticMove, let loc = state.currentLocation {
                    let center = context.camera.centerCoordinate
                    let dist = CLLocation(latitude: center.latitude, longitude: center.longitude)
                        .distance(from: loc)
                    if dist > 50 {
                        followUser = false
                    }
                }
            }
            .onChange(of: state.currentLocation) { _, newLoc in
                guard followUser, let loc = newLoc else { return }
                moveCamera(to: loc.coordinate)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        followUser = true
                        if let loc = state.currentLocation {
                            moveCamera(to: loc.coordinate)
                        }
                    } label: {
                        Image(systemName: followUser ? "location.fill" : "location")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        Button {
                            WKInterfaceDevice.current().play(.click)
                            state.addWaypointAction?()
                        } label: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }
                }
            }
        }
        .onAppear {
            state.isMapVisible = true
            // Perform full sync so the map catches up with any points
            // recorded while it was not visible.
            if state.needsFullSync {
                state.performFullSync?()
            }
            if let loc = state.currentLocation {
                moveCamera(to: loc.coordinate)
            }
        }
        .onDisappear {
            state.isMapVisible = false
        }
    }

    // MARK: - Helpers

    /// Move the camera to a coordinate, debouncing the programmatic-move flag
    /// so overlapping location updates don't create cascading timers.
    private func moveCamera(to coordinate: CLLocationCoordinate2D) {
        // Cancel any pending reset from a previous move
        programmaticMoveResetWork?.cancel()

        isProgrammaticMove = true
        position = .camera(MapCamera(
            centerCoordinate: coordinate,
            distance: cameraDistance
        ))

        let work = DispatchWorkItem { isProgrammaticMove = false }
        programmaticMoveResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
