import Foundation

/// Watches one file for writes, renames and deletions and reports on the main actor.
/// Editors that save atomically replace the inode, so after a delete or rename the
/// monitor re-opens the path a moment later and keeps watching.
///
/// The queue-owned state lives in `Watcher` so this class's `deinit` can cancel it
/// without ever capturing `self` after deallocation has begun.
final class FileChangeMonitor: @unchecked Sendable {
    static let debounceInterval: TimeInterval = 0.25
    static let rearmDelay: TimeInterval = 0.4

    private let watcher: Watcher

    init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        watcher = Watcher(url: url, onChange: onChange)
        watcher.start()
    }

    deinit {
        watcher.cancel()
    }

    func cancel() {
        watcher.cancel()
    }

    private final class Watcher: @unchecked Sendable {
        private let url: URL
        private let onChange: @MainActor @Sendable () -> Void
        private let queue = DispatchQueue(label: "dev.local.skald.filemonitor", qos: .utility)
        private var source: DispatchSourceFileSystemObject?
        private var debounce: DispatchWorkItem?
        private var isCancelled = false

        init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
            self.url = url
            self.onChange = onChange
        }

        func start() {
            queue.async { [self] in arm() }
        }

        func cancel() {
            queue.async { [self] in
                isCancelled = true
                source?.cancel()
                source = nil
                debounce?.cancel()
                debounce = nil
            }
        }

        // MARK: On `queue`

        private func arm() {
            guard !isCancelled else { return }
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                scheduleRearm()
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
                queue: queue
            )
            source.setEventHandler { [weak self, weak source] in
                guard let self, let source else { return }
                let flags = source.data
                self.notifyDebounced()
                if !flags.intersection([.delete, .rename, .revoke]).isEmpty {
                    source.cancel()
                    self.source = nil
                    self.scheduleRearm()
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            self.source = source
            source.resume()
        }

        private func scheduleRearm() {
            queue.asyncAfter(deadline: .now() + FileChangeMonitor.rearmDelay) { [weak self] in
                guard let self, !self.isCancelled, self.source == nil else { return }
                self.arm()
            }
        }

        private func notifyDebounced() {
            debounce?.cancel()
            let handler = onChange
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.isCancelled else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { handler() }
                }
            }
            debounce = item
            queue.asyncAfter(deadline: .now() + FileChangeMonitor.debounceInterval, execute: item)
        }
    }
}
