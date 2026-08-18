import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Foundation
import SwiftData
import UIKit

/// Mirrors this device's entries into a shared Firestore collection keyed
/// by a plain "group code" (see Setup's GROUP section -- there are no
/// real accounts, just a shared code plus a display name), and mirrors
/// every other group member's entries back into this device's local
/// SwiftData store.
///
/// Once merged locally, an entry from a groupmate is indistinguishable
/// to the rest of the app from one captured on this phone -- History,
/// the BOLO/past-sightings checks, and every export already just read
/// from SwiftData, so none of that code needed to change to become
/// group-aware. Photos sync too, via Firebase Storage rather than
/// Firestore (documents aren't meant for blobs) -- but a downscaled
/// copy, not the original. The local photo stays full-resolution;
/// only what leaves the device gets shrunk, to keep Storage's free-
/// tier bandwidth from disappearing into a handful of full-res photos.
@MainActor
final class GroupSyncService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?

    private var listener: ListenerRegistration?
    private var modelContext: ModelContext?
    private var currentGroupCode: String?

    /// False until a `GoogleService-Info.plist` has been added to the
    /// Xcode project and `FirebaseApp.configure()` has run -- see
    /// `PlateLogApp.swift`. Every method below is a no-op when this is
    /// false, so the rest of the app works normally whether or not
    /// Firebase has been set up.
    var isFirebaseConfigured: Bool { FirebaseApp.app() != nil }

    /// Starts (or, if already running for a different code, restarts)
    /// listening to a group. Safe to call on every app launch with
    /// whatever group code is currently saved -- a no-op if empty or if
    /// Firebase isn't configured.
    func start(groupCode: String, context: ModelContext) {
        modelContext = context
        guard isFirebaseConfigured, !groupCode.isEmpty else { return }
        if currentGroupCode == groupCode, isActive { return }
        stop()
        currentGroupCode = groupCode

        if Auth.auth().currentUser != nil {
            attachListener(groupCode: groupCode)
        } else {
            Auth.auth().signInAnonymously { [weak self] _, error in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                self.attachListener(groupCode: groupCode)
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        isActive = false
        currentGroupCode = nil
    }

    /// Pushes a freshly-created local entry up to the group. Call this
    /// right after every local insert while a group is joined -- see
    /// CaptureView's `saveEntry`/`quickLog`. The text fields write
    /// immediately; a photo (if there is one) uploads separately and
    /// doesn't hold up the rest of the sync while it does.
    func push(_ entry: PlateEntry, groupCode: String) {
        guard isFirebaseConfigured, !groupCode.isEmpty else { return }
        collection(for: groupCode).document(entry.id.uuidString).setData(Self.payload(for: entry), merge: true) { [weak self] error in
            if let error {
                self?.lastError = error.localizedDescription
            }
        }
        uploadPhotoIfNeeded(entry, groupCode: groupCode)
    }

    private func collection(for groupCode: String) -> CollectionReference {
        Firestore.firestore().collection("groups").document(groupCode).collection("entries")
    }

    private func storagePath(groupCode: String, entryID: UUID) -> String {
        "groups/\(groupCode)/photos/\(entryID.uuidString).jpg"
    }

    private func uploadPhotoIfNeeded(_ entry: PlateEntry, groupCode: String) {
        guard let photoData = entry.photoData, let resized = Self.downscaledJPEG(from: photoData) else { return }
        let path = storagePath(groupCode: groupCode, entryID: entry.id)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        Storage.storage().reference(withPath: path).putData(resized, metadata: metadata) { [weak self] _, error in
            if let error {
                self?.lastError = error.localizedDescription
                return
            }
            // Only recorded in Firestore once the upload actually
            // succeeds, so a groupmate's listener never sees a
            // photoPath pointing at nothing.
            self?.collection(for: groupCode).document(entry.id.uuidString).setData(["photoPath": path], merge: true)
        }
    }

    /// Downscales to a max dimension of 900pt at moderate JPEG quality
    /// before it ever leaves the device -- the local `photoData` this
    /// reads from is untouched, so nothing about local zoom, PDF export,
    /// or the History thumbnail changes.
    private static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 900, quality: CGFloat = 0.6) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return image.jpegData(compressionQuality: quality) }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality)
    }

    private func attachListener(groupCode: String) {
        listener = collection(for: groupCode).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.isActive = false
                self.lastError = error.localizedDescription
                return
            }
            self.isActive = true
            self.lastError = nil
            // .modified matters here, not just .added: a photo upload
            // finishing attaches `photoPath` to the document in a
            // second write, after the text already synced, so a
            // groupmate sees that as a modification to a document they
            // already have -- not a new one.
            for change in snapshot?.documentChanges ?? [] where change.type == .added || change.type == .modified {
                self.mergeRemote(change.document)
            }
        }
    }

    private func mergeRemote(_ document: QueryDocumentSnapshot) {
        guard let modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()
        let descriptor = FetchDescriptor<PlateEntry>(predicate: #Predicate { $0.id == id })

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            // Already have this one -- the only thing a later change
            // can mean is a photo that finished uploading after the
            // text. `photoData == nil` also protects the device that
            // originally captured this entry: its own listener sees
            // its own writes too, but it already has the full-res
            // local photo and shouldn't have that overwritten by the
            // downscaled synced copy.
            if existing.photoData == nil, let photoPath = data["photoPath"] as? String {
                downloadPhoto(path: photoPath, into: existing)
            }
            return
        }

        guard
            let plateNumber = data["plateNumber"] as? String,
            let state = data["state"] as? String,
            let capturedAtTimestamp = data["capturedAt"] as? Timestamp
        else { return }

        let entry = PlateEntry(
            plateNumber: plateNumber,
            state: state,
            vin: data["vin"] as? String,
            capturedAt: capturedAtTimestamp.dateValue(),
            latitude: data["latitude"] as? Double,
            longitude: data["longitude"] as? Double,
            notes: data["notes"] as? String ?? "",
            tag: data["tag"] as? String ?? "General",
            driverName: data["driverName"] as? String ?? "",
            loggedByName: data["loggedByName"] as? String ?? "Group Member"
        )
        entry.id = id
        modelContext.insert(entry)

        // The entry is already visible (with the same gray placeholder
        // any photo-less entry shows) before this finishes -- the
        // thumbnail just fills in once the download lands, same as any
        // other reactive SwiftData update.
        if let photoPath = data["photoPath"] as? String {
            downloadPhoto(path: photoPath, into: entry)
        }
    }

    private func downloadPhoto(path: String, into entry: PlateEntry) {
        Storage.storage().reference(withPath: path).getData(maxSize: 10 * 1024 * 1024) { [weak self] data, error in
            guard let data else {
                if let error {
                    self?.lastError = error.localizedDescription
                }
                return
            }
            entry.photoData = data
        }
    }

    private static func payload(for entry: PlateEntry) -> [String: Any] {
        var payload: [String: Any] = [
            "plateNumber": entry.plateNumber,
            "state": entry.state,
            "capturedAt": Timestamp(date: entry.capturedAt),
            "notes": entry.notes,
            "tag": entry.tag,
            "driverName": entry.driverName,
            "loggedByName": entry.loggedByName,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let vin = entry.vin { payload["vin"] = vin }
        if let latitude = entry.latitude { payload["latitude"] = latitude }
        if let longitude = entry.longitude { payload["longitude"] = longitude }
        return payload
    }
}
