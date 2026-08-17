import XCTest
@testable import Volu

/// Tallennuspyynnön koodaus. Swiftin oletuskoodaus jättää tyhjän arvon pois
/// pyynnöstä, jolloin palvelin ei voi erottaa tyhjennystä siitä ettei kenttää
/// lähetetty — ja kellosta tuotu mittaus katoaisi pelkästä muokkauksesta.
final class ActivitySavePayloadTests: XCTestCase {
    private func encode(_ payload: ActivitySavePayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func payload(distance: Double?, heartRate: Double?) -> ActivitySavePayload {
        ActivitySavePayload(
            activityType: "run",
            durationMinutes: 45,
            manualKcal: nil,
            occurredAt: "2026-08-17T10:00:00Z",
            notes: nil,
            distanceMeters: distance,
            averageHeartRate: heartRate
        )
    }

    func testEmptyMeasurementsAreSentAsExplicitNull() throws {
        let json = try encode(payload(distance: nil, heartRate: nil))
        XCTAssertTrue(json.keys.contains("distanceMeters"))
        XCTAssertTrue(json.keys.contains("averageHeartRate"))
        XCTAssertTrue(json["distanceMeters"] is NSNull)
        XCTAssertTrue(json["averageHeartRate"] is NSNull)
    }

    func testMeasurementsAreSentWhenPresent() throws {
        let json = try encode(payload(distance: 10250, heartRate: 148))
        XCTAssertEqual(json["distanceMeters"] as? Double, 10250)
        XCTAssertEqual(json["averageHeartRate"] as? Double, 148)
    }

    /// Vapaaehtoiset tekstikentät saavat edelleen puuttua: niillä tyhjä ja
    /// puuttuva tarkoittavat palvelimella samaa, eikä turha null ole tarpeen.
    func testOptionalTextFieldsMayBeOmitted() throws {
        let json = try encode(payload(distance: nil, heartRate: nil))
        XCTAssertFalse(json.keys.contains("notes"))
        XCTAssertFalse(json.keys.contains("manualKcal"))
    }
}
