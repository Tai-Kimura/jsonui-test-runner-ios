import SwiftUI

/// SwiftUI Sliders as sjui and the Dynamic converter emit them
/// (`Slider(value:in:onEditingChanged:)`, no step), for
/// SetSliderValueOnDeviceTests. Each slider's value is shown with six
/// decimals under `v_<id>` and the number of finished drags under `n_<id>`,
/// so a test reads what the app holds, not only what the slider reports.
struct SliderSpec: Identifiable {
    let id: String
    let min: Double
    let max: Double
    let initial: Double
}

let sliderSpecs = [
    SliderSpec(id: "s1to10", min: 1, max: 10, initial: 5),
    SliderSpec(id: "s0to1", min: 0, max: 1, initial: 0),
    SliderSpec(id: "s0to100", min: 0, max: 100, initial: 0),
    SliderSpec(id: "sm5to5", min: -5, max: 5, initial: 0),
    SliderSpec(id: "s0to1000", min: 0, max: 1000, initial: 0),
]

struct SliderRow: View {
    let spec: SliderSpec
    @State private var value: Double
    @State private var finished = 0

    init(spec: SliderSpec) {
        self.spec = spec
        _value = State(initialValue: spec.initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Slider(value: $value, in: spec.min...spec.max, onEditingChanged: { editing in
                if !editing { finished += 1 }
            })
            .accessibilityIdentifier(spec.id)
            HStack {
                Text(String(format: "%.6f", value)).accessibilityIdentifier("v_" + spec.id)
                Text("\(finished)").accessibilityIdentifier("n_" + spec.id)
            }
        }
    }
}

@main
struct SliderProbeApp: App {
    /// `-probe reorder` launches the reorder screen (MoveItemOnDeviceTests); anything else the sliders.
    private var probe: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-probe"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    var body: some Scene {
        WindowGroup {
            if probe == "reorder" {
                ReorderProbeView()
            } else if probe == "libreorder" || probe == "libreorderhandle" {
                LibraryReorderProbeView(usesHandle: probe == "libreorderhandle")
            } else {
                VStack(spacing: 14) {
                    ForEach(sliderSpecs) { SliderRow(spec: $0) }
                }
                .padding(16)
            }
        }
    }
}
