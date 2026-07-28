import Darwin
import Foundation

enum SingleInstanceError: LocalizedError {
    case alreadyRunning
    case cannotCreateLock(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Miaomiao is already running."
        case .cannotCreateLock(let path):
            return "Unable to create the single-instance lock at \(path)."
        }
    }
}

final class SingleInstanceLock {
    private var descriptor: Int32 = -1

    init(name: String = "MiaomiaoDesktopPet") throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Miaomiao", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let lockURL = directory.appendingPathComponent("\(name).lock")
        descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw SingleInstanceError.cannotCreateLock(lockURL.path)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            descriptor = -1
            throw SingleInstanceError.alreadyRunning
        }
        ftruncate(descriptor, 0)
        let processID = "\(ProcessInfo.processInfo.processIdentifier)\n"
        _ = processID.withCString { pointer in
            Darwin.write(descriptor, pointer, strlen(pointer))
        }
    }

    deinit {
        if descriptor >= 0 {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
    }
}
