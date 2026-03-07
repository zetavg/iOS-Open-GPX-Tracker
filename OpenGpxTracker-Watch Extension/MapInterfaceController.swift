//
//  MapInterfaceController.swift
//  OpenGpxTracker-Watch Extension
//
//  WKHostingController that hosts the SwiftUI map view
//  pushed from the main InterfaceController.
//

import WatchKit
import SwiftUI

@available(watchOS 10.0, *)
class MapInterfaceController: WKHostingController<WatchMapContentView> {

    override var body: WatchMapContentView {
        return WatchMapContentView()
    }
}
