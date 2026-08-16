import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import SwiftData

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
/// group-aware. Photos deliberately never leave the device that
/// captured them -- only the text fields sync.
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
    /// CaptureView's `saveEntry`/`quickLog`.
    func push(_ entry: PlateEntry, groupCode: String) {
        guard isFirebaseConfigured, !groupCode.isEmpty else { return }
        collection(for: groupCode).document(entry.id.uuidString).setData(Self.payload(for: entry), merge: true) { [weak self] error in
            if let error {
                self?.lastError = error.localizedDescription
            }
        }
    }

    private func collection(for groupCode: String) -> CollectionReference {
        Firestore.firestore().collection("groups").document(groupCode).collection("entries")
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
            for change in snapshot?.documentChanges ?? [] where change.type == .added {
                self.mergeRemote(change.document)
            }
        }
    }

    /// Only handles `.added` (a brand-new document this device hasn't
    /// seen) -- entries are otherwise immutable once synced, so there's
    /// nothing to reconcile on `.modified`/`.removed` for a personal
    /// group log like this.
    private func mergeRemote(_ document: QueryDocumentSnapshot) {
        guard let modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<PlateEntry>(predicate: #Predicate { $0.id == id })
        guard (try? modelContext.fetch(descriptor))?.isEmpty ?? true else { return }

        let data = document.data()
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
