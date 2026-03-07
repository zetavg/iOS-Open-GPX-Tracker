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
    @State private var isProgrammaticMove: Bool = false

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
                isProgrammaticMove = true
                position = .camera(MapCamera(
                    centerCoordinate: loc.coordinate,
                    distance: cameraDistance
                ))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isProgrammaticMove = false
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        followUser = true
                        centerOnUser()
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
            centerOnUser()
        }
    }

    // MARK: - Helpers

    private func centerOnUser() {
        guard let loc = state.currentLocation else { return }
        isProgrammaticMove = true
        position = .camera(MapCamera(
            centerCoordinate: loc.coordinate,
            distance: cameraDistance
        ))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isProgrammaticMove = false
        }
    }
}
