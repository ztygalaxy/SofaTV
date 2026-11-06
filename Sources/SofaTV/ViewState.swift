import SwiftUI

// Select the property wrapper rather than the same-named SDK macro, whose
// SwiftUIMacros plugin is not shipped with standalone Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
