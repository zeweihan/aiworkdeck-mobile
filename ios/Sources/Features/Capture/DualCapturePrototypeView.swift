#if DEBUG
import SwiftUI

/// Host must keep the normal capture screen paused while presenting this diagnostic view.
/// There is deliberately no Release entry point, automatic capture, Photos save, or upload.
struct DualCapturePrototypeView: View {
    let project: RelayProject?
    let onClose: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var service: DualCaptureService?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tr("dual.prototype.notice")).font(.headline)
                    Text(tr("dual.prototype.limitations")).font(.subheadline).foregroundStyle(.secondary)
                    if let service {
                        HStack(spacing: 8) {
                            preview(service.rearPreview)
                            preview(service.frontPreview)
                        }
                        .frame(height: 260)

                        Text(tr("dual.prototype.status")).font(.headline)
                        Text(tr(service.statusKey, ["reason": service.error ?? ""]))
                            .accessibilityIdentifier("dual.prototype.status")
                        ViewThatFits(in: .horizontal) {
                            HStack { controls(service) }
                            VStack(alignment: .leading) { controls(service) }
                        }
                        .buttonStyle(.bordered)

                        Text(tr("dual.prototype.details")).font(.headline)
                        Text(service.diagnostics).font(.caption.monospaced()).textSelection(.enabled)
                        if let url = service.outputURL {
                            Text(tr("dual.prototype.output")).font(.headline)
                            Text(url.path).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(tr("dual.prototype.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("dual.prototype.close")) {
                        let stop = service?.stop()
                        Task { @MainActor in
                            await stop?.value
                            onClose()
                        }
                    }
                }
            }
        }
        // Swipe dismissal cannot await camera release; the close button above does.
        .interactiveDismissDisabled()
        .task {
            // Initializing in the task avoids constructing capture sessions during body rebuilds.
            if service == nil { service = DualCaptureService() }
        }
        .onDisappear { service?.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { service?.stop() }
        }
        .onChange(of: service?.captureConflict) { _, conflict in
            if conflict == true { service?.stop() }
        }
    }

    @ViewBuilder
    private func controls(_ service: DualCaptureService) -> some View {
        Button(tr("dual.prototype.start")) { Task { await service.start() } }
            .disabled(service.isBusy || service.isRunning)
            .accessibilityIdentifier("dual.prototype.start")
        Button(tr("dual.prototype.capture")) { service.capture(project: project) }
            .disabled(!service.isRunning || service.isCapturing || service.isBusy)
            .accessibilityIdentifier("dual.prototype.capture")
        Button(tr("dual.prototype.stop")) { service.stop() }
            .disabled(!service.isRunning && !service.isBusy)
    }

    private func preview(_ data: Data?) -> some View {
        ZStack {
            Color.black
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "camera").foregroundStyle(.gray)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
#endif
