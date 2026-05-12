import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

final class UserManager: ObservableObject {
    
    @Published var hasProfile: Bool? = nil  // nil: 未判定, true/false: 判定済み
    
    /// configure より前に `Firestore.firestore()` を触らないよう lazy にする（起動順問題の回避）
    private lazy var db = Firestore.firestore()
    
    /// ログイン中ユーザーのプロフィールを Firestore に保存 / 更新
    func saveUserProfile(user: User, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let firebaseUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "UserManager",
                                        code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "ログインユーザーが見つかりません。"])))
            return
        }
        
        // FirestoreEncoder (FirebaseFirestoreSwift) が無い環境でも動くよう、辞書で明示的に保存
        var data: [String: Any] = [
            "id": user.id.uuidString,
            "name": user.name,
            "profileImage": user.profileImage,
            "bio": user.bio,
            "rank": user.rank,
            "age": user.age,
            "gender": user.gender,
            "purpose": user.purpose,
            "prefecture": user.prefecture,
            "area": user.area,
            "pace": user.pace,
            "runningFrequency": user.runningFrequency,
            "personalBest": user.personalBest,
            "schedule": user.schedule,
            "nextRace": user.nextRace,
            "targetTime": user.targetTime,
            "monthlyDistance": user.monthlyDistance,
            "monthlyTarget": user.monthlyTarget,
            "avgPace": user.avgPace,
            "matchRate": user.matchRate,
            "lastLogin": Timestamp(date: user.lastLogin),
            "spotName": user.spotName,
            "latitude": user.latitude,
            "longitude": user.longitude,
            "distanceFromUserMock": user.distanceFromUserMock,
            "totalPoints": user.totalPoints,
            "monthlyPoints": user.monthlyPoints
        ]
        
        // profileImageUrl が存在する場合のみ追加
        if let profileImageUrl = user.profileImageUrl {
            data["profileImageUrl"] = profileImageUrl
        }
        if let monthlyGps = user.monthlyGpsActivityCount {
            data["monthlyGpsActivityCount"] = monthlyGps
        }

        let uid = firebaseUser.uid
        let userRef = db.collection("users").document(uid)
        let publicRef = db.collection("public_profiles").document(uid)
        var publicData = data
        publicData.removeValue(forKey: "latitude")
        publicData.removeValue(forKey: "longitude")
        publicData.removeValue(forKey: "distanceFromUserMock")

        let batch = db.batch()
        batch.setData(data, forDocument: userRef, merge: true)
        batch.setData(publicData, forDocument: publicRef, merge: true)
        batch.commit { [weak self] error in
            if let error = error {
                completion(.failure(error))
            } else {
                DispatchQueue.main.async {
                    self?.hasProfile = true
                }
                completion(.success(()))
            }
        }
    }
    
    /// Firestore にプロフィールが存在するか確認
    func checkUserExists() {
        guard let firebaseUser = Auth.auth().currentUser else {
            DispatchQueue.main.async {
                self.hasProfile = nil
            }
            return
        }
        
        db.collection("users").document(firebaseUser.uid).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to check user existence: \(error.localizedDescription)")
                    self?.hasProfile = false
                    return
                }
                self?.hasProfile = snapshot?.exists ?? false
            }
        }
    }
    
    /// Firestore にプロフィールが存在するか確認（非同期版）
    func checkIfUserExists(uid: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            db.collection("users").document(uid).getDocument { snapshot, error in
                if let error = error {
                    print("Failed to check user existence: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: snapshot?.exists ?? false)
            }
        }
    }

    /// ログイン中ユーザーの `users/{uid}` を `User` に読み込む
    func fetchCurrentUserProfile(completion: @escaping (Result<User, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "UserManager",
                                        code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "ログインユーザーが見つかりません。"])))
            return
        }
        db.collection("users").document(uid).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = snapshot?.data(), snapshot?.exists == true else {
                completion(.failure(NSError(domain: "UserManager",
                                              code: -2,
                                              userInfo: [NSLocalizedDescriptionKey: "プロフィールが見つかりません。"])))
                return
            }
            do {
                let user = try Self.parseUserFromFirestoreData(data, firebaseUid: uid)
                completion(.success(user))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchCurrentUserProfile() async throws -> User {
        try await withCheckedThrowingContinuation { continuation in
            fetchCurrentUserProfile { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Find タブ用: `public_profiles` から他ユーザーの公開プロフィールを取得（自分の UID は除外）
    func fetchDiscoverUsers(limit: Int = 80, completion: @escaping (Result<[User], Error>) -> Void) {
        guard let myUid = Auth.auth().currentUser?.uid else {
            completion(.success([]))
            return
        }
        db.collection("public_profiles")
            .limit(to: max(1, min(limit, 100)))
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                var users: [User] = []
                for doc in snapshot?.documents ?? [] {
                    if doc.documentID == myUid { continue }
                    do {
                        let user = try Self.parseUserFromFirestoreData(doc.data(), firebaseUid: doc.documentID)
                        users.append(user)
                    } catch {
                        continue
                    }
                }
                completion(.success(users))
            }
    }

    func fetchDiscoverUsers(limit: Int = 80) async throws -> [User] {
        try await withCheckedThrowingContinuation { continuation in
            fetchDiscoverUsers(limit: limit) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static func parseUserFromFirestoreData(_ data: [String: Any], firebaseUid: String? = nil) throws -> User {
        guard let idStr = data["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw NSError(domain: "UserManager",
                          code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "ユーザーIDの形式が不正です。"])
        }

        let lastLogin: Date
        if let ts = data["lastLogin"] as? Timestamp {
            lastLogin = ts.dateValue()
        } else {
            lastLogin = Date()
        }

        let monthlyGps: Int?
        if let n = data["monthlyGpsActivityCount"] as? Int {
            monthlyGps = n
        } else if let n = data["monthlyGpsActivityCount"] as? NSNumber {
            monthlyGps = n.intValue
        } else {
            monthlyGps = nil
        }

        return User(
            id: uuid,
            name: data["name"] as? String ?? "",
            profileImage: data["profileImage"] as? String ?? "runner",
            profileImageUrl: data["profileImageUrl"] as? String,
            bio: data["bio"] as? String ?? "",
            rank: data["rank"] as? String ?? "Rank E",
            age: intFromFirestore(data["age"]),
            gender: data["gender"] as? String ?? "無回答",
            purpose: data["purpose"] as? String ?? "",
            prefecture: data["prefecture"] as? String ?? "",
            area: data["area"] as? String ?? "",
            pace: data["pace"] as? String ?? "",
            runningFrequency: data["runningFrequency"] as? String ?? "",
            personalBest: data["personalBest"] as? String ?? "",
            schedule: data["schedule"] as? String ?? "",
            nextRace: data["nextRace"] as? String ?? "",
            targetTime: data["targetTime"] as? String ?? "",
            monthlyDistance: doubleFromFirestore(data["monthlyDistance"]),
            monthlyTarget: doubleFromFirestore(data["monthlyTarget"]),
            avgPace: data["avgPace"] as? String ?? "",
            totalPoints: intFromFirestore(data["totalPoints"]),
            monthlyPoints: intFromFirestore(data["monthlyPoints"]),
            matchRate: intFromFirestore(data["matchRate"]),
            lastLogin: lastLogin,
            spotName: data["spotName"] as? String ?? (data["area"] as? String ?? ""),
            latitude: doubleFromFirestore(data["latitude"]),
            longitude: doubleFromFirestore(data["longitude"]),
            distanceFromUserMock: doubleFromFirestore(data["distanceFromUserMock"]),
            monthlyGpsActivityCount: monthlyGps,
            firebaseUid: firebaseUid
        )
    }

    private static func intFromFirestore(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }

    private static func doubleFromFirestore(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return 0
    }
}
