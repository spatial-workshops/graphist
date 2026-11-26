import SwiftUI

/// Contents of one window: the Metal canvas plus a toolbar to pick the scene.
struct CanvasWindow: View {
    @State private var sceneID = SceneCatalog.defaultID
    @State private var generation = 0
    @State private var stats = RenderStats()
    @State private var showsStats = false

    var body: some View {
        MetalCanvas(sceneID: sceneID, generation: generation, stats: stats)
            .ignoresSafeArea()
            .overlay(alignment: .bottomLeading) {
                if showsStats { StatsOverlay(stats: stats) }
            }
            .overlay(alignment: .top) {
                ErrorOverlay(stats: stats)
            }
            .navigationTitle(SceneCatalog.entry(id: sceneID)?.title ?? "Graphist")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Scene", selection: $sceneID) {
                        ForEach(SceneCatalog.all, id: \.id) { entry in
                            Text(entry.title).tag(entry.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Choose what this window renders")

                    Button {
                        generation += 1
                    } label: {
                        Label("Reload Scene", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Recreate the scene (recompiles shaders in live-source mode)")

                    Toggle(isOn: $showsStats) {
                        Label("Stats", systemImage: "speedometer")
                    }
                    .help("Show frame rate")
                }
            }
            .frame(minWidth: 320, minHeight: 240)
    }
}

private struct StatsOverlay: View {
    let stats: RenderStats

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f fps  (%.2f ms)", stats.framesPerSecond, stats.frameTimeMilliseconds))
            Text(stats.resolution)
            Text(stats.shaderSource)
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white.opacity(0.9))
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 10))
        .padding(12)
        .allowsHitTesting(false)
    }
}

private struct ErrorOverlay: View {
    let stats: RenderStats

    var body: some View {
        if let message = stats.errorMessage {
            ScrollView {
                Text(message)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .padding(14)
            .background(.red.opacity(0.75), in: .rect(cornerRadius: 12))
            .padding(16)
        }
    }
}
