//
//  MapsLauncher.swift
//  Hitoashi
//
//  「マップ」を徒歩の経路で開く。
//

import CoreLocation
import HitoashiKit
import MapKit

enum MapsLauncher {
    /// スポットまでの徒歩の経路を「マップ」で開く
    static func openWalkingDirections(to spot: Spot) {
        let location = CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = spot.name
        _ = item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

extension Coordinate {
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
