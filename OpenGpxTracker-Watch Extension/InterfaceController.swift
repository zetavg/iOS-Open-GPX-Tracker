//
//  InterfaceController.swift
//  OpenGpxTracker-Watch Extension
//
//  Created by Vincent on 5/2/19.
//  Copyright © 2019 TransitBox. All rights reserved.
//

import WatchKit
import MapKit
import CoreLocation
import CoreGPX
import WatchConnectivity

// Button colors
let kPurpleButtonBackgroundColor: UIColor =  UIColor(red: 146.0/255.0, green: 166.0/255.0, blue: 218.0/255.0, alpha: 0.90)
let kGreenButtonBackgroundColor: UIColor = UIColor(red: 142.0/255.0, green: 224.0/255.0, blue: 102.0/255.0, alpha: 0.90)
let kRedButtonBackgroundColor: UIColor =  UIColor(red: 244.0/255.0, green: 94.0/255.0, blue: 94.0/255.0, alpha: 0.90)
let kBlueButtonBackgroundColor: UIColor = UIColor(red: 74.0/255.0, green: 144.0/255.0, blue: 226.0/255.0, alpha: 0.90)
let kDisabledBlueButtonBackgroundColor: UIColor = UIColor(red: 74.0/255.0, green: 144.0/255.0, blue: 226.0/255.0, alpha: 0.10)
let kDisabledRedButtonBackgroundColor: UIColor =  UIColor(red: 244.0/255.0, green: 94.0/255.0, blue: 94.0/255.0, alpha: 0.10)
let kWhiteBackgroundColor: UIColor = UIColor(red: 254.0/255.0, green: 254.0/255.0, blue: 254.0/255.0, alpha: 0.90)

// Accesory View buttons tags
let kDeleteWaypointAccesoryButtonTag = 666
let kEditWaypointAccesoryButtonTag = 333

let kNotGettingLocationText = NSLocalizedString("NO_LOCATION", comment: "no comment")
let kUnknownAccuracyText = "±···"
let kUnknownSpeedText = "·.··"
let kUnknownAltitudeText = "···"

/// Size for small buttons
let kButtonSmallSize: CGFloat = 48.0
/// Size for large buttons
let kButtonLargeSize: CGFloat = 96.0
/// Separation between buttons
let kButtonSeparation: CGFloat = 6.0

/// Upper limits threshold (in meters) on signal accuracy.
let kSignalAccuracy6 = 6.0
let kSignalAccuracy5 = 11.0
let kSignalAccuracy4 = 31.0
let kSignalAccuracy3 = 51.0
let kSignalAccuracy2 = 101.0
let kSignalAccuracy1 = 201.0

///
/// Main View Controller of the Watch Application. It is loaded when the application is launched
///
/// Displays a set the buttons to control the tracking, along with additional infomation.
///
///
class InterfaceController: WKInterfaceController {

    @IBOutlet var newPinButton: WKInterfaceButton!
    @IBOutlet var trackerButton: WKInterfaceButton!
    @IBOutlet var saveButton: WKInterfaceButton!
    @IBOutlet var resetButton: WKInterfaceButton!
    @IBOutlet var timeLabel: WKInterfaceLabel!
    @IBOutlet var totalTrackedDistanceLabel: WKInterfaceLabel!
    @IBOutlet var signalImageView: WKInterfaceImage!
    @IBOutlet var signalAccuracyLabel: WKInterfaceLabel!
    @IBOutlet var coordinatesLabel: WKInterfaceLabel!
    @IBOutlet var altitudeLabel: WKInterfaceLabel!
    @IBOutlet var speedLabel: WKInterfaceLabel!

    /// Location Manager
    let locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.requestAlwaysAuthorization()

        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2 // meters
        manager.allowsBackgroundLocationUpdates = true
        return manager
    }()

    /// Preferences loader
    let preferences = Preferences.shared

    /// Underlying class that handles background stuff
    let map = GPXMapView() // not even a map view. Considering renaming

    // Status Vars
    var trackStartDate: Date?
    var stopWatch = StopWatch()
    var lastGpxFilename: String = ""
    var wasSentToBackground: Bool = false // Was the app sent to background
    var isDisplayingLocationServicesDenied: Bool = false

    /// Timestamp of the last recovery-file persist, used to throttle writes and save battery.
    var lastPersistTime: Date = .distantPast

    /// Does the 'file' have any waypoint?
    var hasWaypoints: Bool = false {
        /// Whenever it is updated, if it has waypoints it sets the save and reset button
        didSet {
            if hasWaypoints {
                saveButton.setBackgroundColor(kBlueButtonBackgroundColor)
                resetButton.setBackgroundColor(kRedButtonBackgroundColor)
            }
        }
    }

    /// Whether the session has data that hasn't been saved to a GPX file yet.
    var hasUnsavedChanges: Bool = false

    // Signal accuracy images
    let signalImage0 = UIImage(named: "signal0")
    let signalImage1 = UIImage(named: "signal1")
    let signalImage2 = UIImage(named: "signal2")
    let signalImage3 = UIImage(named: "signal3")
    let signalImage4 = UIImage(named: "signal4")
    let signalImage5 = UIImage(named: "signal5")
    let signalImage6 = UIImage(named: "signal6")

    /// Defines the different statuses regarding tracking current user location.
    enum GpxTrackingStatus {

        /// Tracking has not started or map was reset
        case notStarted

        /// Tracking is ongoing
        case tracking

        /// Tracking is paused (the map has some contents)
        case paused
    }

    /// Tells what is the current status of the Map Instance.
    var gpxTrackingStatus: GpxTrackingStatus = GpxTrackingStatus.notStarted {
        didSet {
            print("gpxTrackingStatus changed to \(gpxTrackingStatus)")
            switch gpxTrackingStatus {
            case .notStarted:
                print("switched to non started")
                // set Tracker button to allow Start
                trackerButton.setTitle(NSLocalizedString("START_TRACKING", comment: "no comment"))
                trackerButton.setBackgroundColor(kGreenButtonBackgroundColor)
                // Save & reset button to transparent.
                saveButton.setBackgroundColor(kDisabledBlueButtonBackgroundColor)
                resetButton.setBackgroundColor(kDisabledRedButtonBackgroundColor)
                // Reset clock
                stopWatch.reset()
                timeLabel.setText(stopWatch.elapsedTimeString)

                map.reset() // Reset gpx logging
                trackStartDate = nil // Clear track start date
                lastGpxFilename = "" // Clear last filename, so when saving it appears an empty field
                hasUnsavedChanges = false

                totalTrackedDistanceLabel.setText(map.totalTrackedDistance.toDistance(useImperial: preferences.useImperial))

            case .tracking:
                print("switched to tracking mode")
                // set trackerButton to allow Pause
                trackerButton.setTitle(NSLocalizedString("PAUSE", comment: "no comment"))
                trackerButton.setBackgroundColor(kPurpleButtonBackgroundColor)
                // Activate save & reset buttons
                saveButton.setBackgroundColor(kBlueButtonBackgroundColor)
                resetButton.setBackgroundColor(kRedButtonBackgroundColor)
                // Capture tracking start time on first start
                if trackStartDate == nil {
                    trackStartDate = Date()
                }
                // start clock
                self.stopWatch.start()

            case .paused:
                print("switched to paused mode")
                // set trackerButton to allow Resume
                self.trackerButton.setTitle(NSLocalizedString("RESUME", comment: "no comment"))
                self.trackerButton.setBackgroundColor(kGreenButtonBackgroundColor)
                // activate save & reset (just in case switched from .NotStarted)
                saveButton.setBackgroundColor(kBlueButtonBackgroundColor)
                resetButton.setBackgroundColor(kRedButtonBackgroundColor)
                // Pause clock
                self.stopWatch.stop()
                // start new track segment
                self.map.startNewTrackSegment()
            }
        }
    }

    /// Editing Waypoint Temporal Reference
    var lastLocation: CLLocation? // Last point of current segment.

    override func awake(withContext context: Any?) {
        print("InterfaceController:: awake")
        super.awake(withContext: context)

        totalTrackedDistanceLabel.setText( 0.00.toDistance(useImperial: preferences.useImperial))

        if gpxTrackingStatus == .notStarted {
            trackerButton.setBackgroundColor(kGreenButtonBackgroundColor)
            newPinButton.setBackgroundColor(kWhiteBackgroundColor)
            saveButton.setBackgroundColor(kDisabledRedButtonBackgroundColor)
            resetButton.setBackgroundColor(kDisabledBlueButtonBackgroundColor)

            coordinatesLabel.setText(kNotGettingLocationText)
            signalAccuracyLabel.setText(kUnknownAccuracyText)
            altitudeLabel.setText(kUnknownAltitudeText)
            speedLabel.setText(kUnknownSpeedText)
            signalImageView.setImage(signalImage0)
        }

        // Attempt crash/force-quit recovery
        attemptSessionRecovery()
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
         print("InterfaceController:: willActivate")
        super.willActivate()
        self.setTitle(NSLocalizedString("GPX_TRACKER", comment: "no comment"))

        stopWatch.delegate = self

        locationManager.delegate = self
        checkLocationServicesStatus()
        locationManager.startUpdatingLocation()

    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
        print("InterfaceController:: didDeactivate called")

        // Persist session before deactivation as an extra safety net.
        if gpxTrackingStatus != .notStarted {
            persistSessionForRecovery(force: true)
        }

        if gpxTrackingStatus != .tracking {
            print("InterfaceController:: didDeactivate will stopUpdatingLocation")
            locationManager.stopUpdatingLocation()
        }
    }

    ///
    /// Main Start/Pause Button was tapped.
    ///
    /// It sets the status to tracking or paused.
    ///
    @IBAction func trackerButtonTapped() {
        print("startGpxTracking::")
        switch gpxTrackingStatus {
        case .notStarted:
            gpxTrackingStatus = .tracking
            WKInterfaceDevice.current().play(.start)
        case .tracking:
            gpxTrackingStatus = .paused
            WKInterfaceDevice.current().play(.stop)
        case .paused:
            // Set to tracking
            gpxTrackingStatus = .tracking
            WKInterfaceDevice.current().play(.start)
        }

    }

    ///
    /// Add Pin (waypoint) Button was tapped.
    ///
    /// It adds a new waypoint with the current coordinates while tracking is underway.
    ///
    @IBAction func addPinAtMyLocation() {
        if let currentCoordinates = locationManager.location?.coordinate {
            let altitude = locationManager.location?.altitude
            let waypoint = GPXWaypoint(coordinate: currentCoordinates, altitude: altitude)
            map.addWaypoint(waypoint)
            print("Adding waypoint at \(currentCoordinates)")
            self.hasWaypoints = true
            self.hasUnsavedChanges = true
            persistSessionForRecovery(force: true)
            WKInterfaceDevice.current().play(.directionUp)
            newPinButton.setTitle("✓")
            newPinButton.setBackgroundColor(kGreenButtonBackgroundColor)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.newPinButton.setTitle("📍")
                self.newPinButton.setBackgroundColor(kWhiteBackgroundColor)
            }
        }

    }

    ///
    /// Save Button was tapped.
    ///
    /// If auto-save counter is enabled and the track was previously saved,
    /// it automatically saves with a counter suffix (e.g. `-1`, `-2`, etc.).
    /// Otherwise saves with the default filename.
    ///
    @IBAction func saveButtonTapped() {
        print("save Button tapped")
        // ignore the save button if there is nothing to save.
        if (gpxTrackingStatus == .notStarted) && !self.hasWaypoints {
            return
        }

        let filename: String
        if preferences.autoSaveCounter && !lastGpxFilename.isEmpty {
            filename = GPXFileManager.nextAvailableFilename(for: lastGpxFilename)
        } else {
            filename = defaultFilename()
        }

        let gpxString = self.map.exportToGPXString()
        GPXFileManager.save(filename, gpxContents: gpxString)
        self.lastGpxFilename = filename
        self.hasUnsavedChanges = false
        // Re-persist recovery immediately so continued tracking after save is protected.
        // (Clearing alone would leave a window with no recovery file until the next GPS update.)
        persistSessionForRecovery(force: true)
        WKInterfaceDevice.current().play(.success)
        // print(gpxString)

        // Automatically send the saved file to the iOS app
        sendSavedFileToiOS(filename: filename)

        /// Just a 'done' button, without
        let action = WKAlertAction(title: "Done", style: .default) {}

        presentAlert(withTitle: NSLocalizedString("FILE_SAVED_TITLE", comment: "no comment"),
                     message: "\(filename).gpx", preferredStyle: .alert, actions: [action])

    }

    ///
    /// Triggered when reset button was tapped.
    ///
    /// It sets map to status .notStarted which clears the map.
    ///
    @IBAction func resetButtonTapped() {
        WKInterfaceDevice.current().play(.click)

        // If there are no unsaved changes, reset immediately without confirmation.
        guard hasUnsavedChanges else {
            self.gpxTrackingStatus = .notStarted
            WatchSessionRecovery.clear()
            return
        }

        let cancelOption = WKAlertAction(title: NSLocalizedString("CANCEL", comment: "no comment"), style: .cancel) {}
        let deleteOption = WKAlertAction(title: NSLocalizedString("RESET", comment: "no comment"), style: .destructive) {
            self.gpxTrackingStatus = .notStarted
            WatchSessionRecovery.clear()
        }
        let dismissOption = WKAlertAction(title: NSLocalizedString("CANCEL", comment: "no comment"), style: .default) {}

        presentAlert(withTitle: nil,
                     message: NSLocalizedString("RESET_UNSAVED_CHANGES", comment: "no comment"),
                     preferredStyle: .actionSheet,
                     actions: [cancelOption, deleteOption, dismissOption])
    }

    /// returns a string with the format based on user preferences (matching iOS app behavior)
    ///
    func defaultFilename() -> String {
        let defaultDate = DefaultDateFormat()
        let dateStr = defaultDate.getDateFromPrefs(date: trackStartDate ?? Date())
        print("fileName:" + dateStr)
        return dateStr
    }

    ///
    /// Checks the location services status
    /// - Are location services enabled (access to location device wide)? If not => displays an alert
    /// - Are location services allowed to this app? If not => displays an alert
    ///
    /// - Seealso: displayLocationServicesDisabledAlert, displayLocationServicesDeniedAlert
    ///
    func checkLocationServicesStatus() {
        let authorizationStatus = CLLocationManager.authorizationStatus()

        // Has the user already made a permission choice?
        guard authorizationStatus != .notDetermined else {
            // We should take no action until the user has made a choice
            return
        }

        // Does the app have permissions to use the location servies?
        guard [.authorizedAlways, .authorizedWhenInUse ].contains(authorizationStatus) else {
            displayLocationServicesDeniedAlert()
            return
        }

        // Are location services enabled?
        guard CLLocationManager.locationServicesEnabled() else {
            displayLocationServicesDisabledAlert()
            return
        }
    }

    ///
    /// Displays an alert that informs the user that location services are disabled.
    ///
    /// When location services are disabled is for all applications, not only this one.
    ///
    func displayLocationServicesDisabledAlert() {
        let button = WKAlertAction(title: "Cancel", style: .cancel) {
            print("LocationServicesDisabledAlert: cancel pressed")
        }

        presentAlert(withTitle: NSLocalizedString("LOCATION_SERVICES_DISABLED", comment: "no comment"),
                     message: NSLocalizedString("ENABLE_LOCATION_SERVICES", comment: "no comment"),
                     preferredStyle: .alert, actions: [button])
    }

    ///
    /// Displays an alert that informs the user that access to location was denied for this app (other apps may have access).
    /// It also dispays a button allows the user to go to settings to activate the location.
    ///
    func displayLocationServicesDeniedAlert() {
        if isDisplayingLocationServicesDenied {
            return // display it only once.
        }
        let button = WKAlertAction(title: "Cancel", style: .cancel) {
            print("LocationServicesDeniedAlert: cancel pressed")
        }

        presentAlert(withTitle: NSLocalizedString("ACCESS_TO_LOCATION_DENIED", comment: "no comment"),
                     message: NSLocalizedString("ALLOW_LOCATION", comment: "no comment"),
                     preferredStyle: .alert, actions: [button])
    }

    // MARK: - Auto-send to iOS

    /// Sends the just-saved GPX file to the paired iOS app via WatchConnectivity.
    ///
    /// The transfer is enqueued in the background. If the iOS app is not reachable
    /// at the moment, the system will deliver the file when connectivity is restored.
    func sendSavedFileToiOS(filename: String) {
        guard WCSession.isSupported() else {
            print("InterfaceController:: WCSession not supported, skipping auto-send")
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("InterfaceController:: WCSession not activated, skipping auto-send")
            return
        }
        let fileURL = GPXFileManager.URLForFilename(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("InterfaceController:: saved file not found at \(fileURL), skipping auto-send")
            return
        }
        print("InterfaceController:: auto-sending \(filename).gpx to iOS app")
        session.transferFile(fileURL, metadata: ["fileName": "\(filename).gpx"])
    }
}

// MARK: StopWatchDelegate

///
/// Updates the `timeLabel` with the `stopWatch` elapsedTime.
/// In the main ViewController there is a label that holds the elapsed time, that is, the time that
/// user has been tracking his position.
///
///
extension InterfaceController: StopWatchDelegate {
    func stopWatch(_ stropWatch: StopWatch, didUpdateElapsedTimeString elapsedTimeString: String) {
        timeLabel.setText(elapsedTimeString)
    }
}

// MARK: CLLocationManagerDelegate

extension InterfaceController: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("didFailWithError \(error)")
        coordinatesLabel.setText(kNotGettingLocationText)
        signalAccuracyLabel.setText(kUnknownAccuracyText)
        altitudeLabel.setText(kUnknownAltitudeText)
        signalImageView.setImage(signalImage0)
        speedLabel.setText(kUnknownSpeedText)
        let locationError = error as? CLError
        switch locationError?.code {
        case CLError.locationUnknown:
            print("Location Unknown")
        case CLError.denied:
            print("Access to location services denied. Display message")
            checkLocationServicesStatus()
        case CLError.headingFailure:
            print("Heading failure")
        default:
            print("Default error")
        }

    }

    ///
    /// Updates location accuracy and map information when user is in a new position
    ///
    ///
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Updates signal image accuracy
        let newLocation = locations.first!

        let hAcc = newLocation.horizontalAccuracy
        let vAcc = newLocation.verticalAccuracy
        print("didUpdateLocation: received \(newLocation.coordinate) hAcc: \(hAcc) vAcc: \(vAcc) floor: \(newLocation.floor?.description ?? "''")")

        signalAccuracyLabel.setText(hAcc.toAccuracy(useImperial: preferences.useImperial))
        if hAcc < kSignalAccuracy6 {
            self.signalImageView.setImage(signalImage6)
        } else if hAcc < kSignalAccuracy5 {
            self.signalImageView.setImage(signalImage5)
        } else if hAcc < kSignalAccuracy4 {
            self.signalImageView.setImage(signalImage4)
        } else if hAcc < kSignalAccuracy3 {
            self.signalImageView.setImage(signalImage3)
        } else if hAcc < kSignalAccuracy2 {
            self.signalImageView.setImage(signalImage2)
        } else if hAcc < kSignalAccuracy1 {
            self.signalImageView.setImage(signalImage1)
        } else {
            self.signalImageView.setImage(signalImage0)
        }

        // Update coordsLabels
        let latFormat = String(format: "%.6f", newLocation.coordinate.latitude)
        let lonFormat = String(format: "%.6f", newLocation.coordinate.longitude)

        coordinatesLabel.setText("\(latFormat),\(lonFormat)")
        altitudeLabel.setText(newLocation.altitude.toAltitude(useImperial: preferences.useImperial))

        // Update speed (provided in m/s, but displayed in km/h)
        speedLabel.setText(newLocation.speed.toSpeed(useImperial: preferences.useImperial))

        if gpxTrackingStatus == .tracking {
            print("didUpdateLocation: adding point to track (\(newLocation.coordinate.latitude),\(newLocation.coordinate.longitude))")
            map.addPointToCurrentTrackSegmentAtLocation(newLocation)
            hasUnsavedChanges = true
            totalTrackedDistanceLabel.setText(map.totalTrackedDistance.toDistance(useImperial: preferences.useImperial))
            persistSessionForRecovery(force: false)
        }
    }
}

// MARK: - Session Recovery

extension InterfaceController {

    /// How often (in seconds) the recovery file is written during continuous tracking.
    /// Waypoint additions, saves, and lifecycle events always persist immediately.
    private static let recoveryPersistInterval: TimeInterval = 60

    /// Persist the current session so it can be recovered after a crash or force-quit.
    ///
    /// - Parameter force: When `true`, writes immediately (used for user actions and
    ///   lifecycle events). When `false`, writes are throttled to at most once per
    ///   `recoveryPersistInterval` seconds to conserve battery on Apple Watch.
    func persistSessionForRecovery(force: Bool) {
        if !force {
            let now = Date()
            guard now.timeIntervalSince(lastPersistTime) >= Self.recoveryPersistInterval else {
                return // skip — too soon since last persist
            }
            lastPersistTime = now
        } else {
            lastPersistTime = Date()
        }

        WatchSessionRecovery.save(
            session: map,
            trackStartDate: trackStartDate,
            elapsedTime: stopWatch.elapsedTime,
            isTracking: gpxTrackingStatus == .tracking,
            lastGpxFilename: lastGpxFilename,
            hasWaypoints: hasWaypoints,
            hasUnsavedChanges: hasUnsavedChanges
        )
    }

    /// On launch, check for a recovery file and restore the session in paused state.
    func attemptSessionRecovery() {
        guard let recovered = WatchSessionRecovery.recover() else { return }

        print("InterfaceController:: recovering session from previous crash/exit")

        // Restore session data (tracks, waypoints)
        map.continueFromGPXRoot(recovered.gpxRoot)

        // Restore waypoints that are in the GPXRoot but not yet in the session's waypoints array
        // (continueFromGPXRoot handles tracks/segments; waypoints need separate handling)
        for wpt in recovered.gpxRoot.waypoints {
            map.addWaypoint(wpt)
        }

        // Restore metadata
        trackStartDate = recovered.metadata.trackStartDate
        lastGpxFilename = recovered.metadata.lastGpxFilename
        hasWaypoints = recovered.metadata.hasWaypoints

        // Update distance display
        totalTrackedDistanceLabel.setText(map.totalTrackedDistance.toDistance(useImperial: preferences.useImperial))

        // Switch to paused FIRST — the .paused setter calls stopWatch.stop() which
        // adds (Date.timeIntervalSinceReferenceDate - startedTime) to tmpElapsedTime.
        // Since startedTime is 0 on a fresh StopWatch, that would produce a huge value.
        // So we set the correct tmpElapsedTime AFTER the .paused assignment.
        gpxTrackingStatus = .paused
        hasUnsavedChanges = recovered.metadata.hasUnsavedChanges
        stopWatch.tmpElapsedTime = recovered.metadata.elapsedTime
        timeLabel.setText(stopWatch.elapsedTimeString)

        print("InterfaceController:: session recovered with \(recovered.gpxRoot.tracks.count) track(s), \(recovered.gpxRoot.waypoints.count) waypoint(s), elapsed: \(recovered.metadata.elapsedTime)s")
    }
}
