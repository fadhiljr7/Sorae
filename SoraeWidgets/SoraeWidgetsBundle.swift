//
//  SoraeWidgetsBundle.swift
//  SoraeWidgets
//
//  The extension exists only to host the Live Activity — there is no home
//  screen widget.
//

import SwiftUI
import WidgetKit

@main
struct SoraeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SoraeLiveActivity()
    }
}
