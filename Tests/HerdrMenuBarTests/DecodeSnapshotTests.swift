import XCTest
@testable import HerdrMenuBar

final class DecodeSnapshotTests: XCTestCase {
    private typealias JSONObject = [String: Any]

    func testDecodesAgentWithAllFields() throws {
        let json: JSONObject = [
            "agents": [[
                "pane_id": "w3Y:p12",
                "workspace_id": "w3Y",
                "agent": "claude",
                "name": "refactor",
                "agent_status": "working",
                "terminal_title_stripped": "claude · refactor",
                "foreground_cwd": "/tmp/work",
            ]],
            "workspaces": [["workspace_id": "w3Y", "label": "main", "number": 3]],
            "panes": [["pane_id": "w3Y:p12"]],
        ]

        let snapshot = HerdrClient.decodeSnapshot(json)

        XCTAssertEqual(snapshot.agents.count, 1)
        let agent = try XCTUnwrap(snapshot.agents.first)
        XCTAssertEqual(agent.paneID, "w3Y:p12")
        XCTAssertEqual(agent.workspaceID, "w3Y")
        XCTAssertEqual(agent.kind, "claude")
        XCTAssertEqual(agent.name, "refactor")
        XCTAssertEqual(agent.status, .working)
        XCTAssertEqual(agent.title, "claude · refactor")
        XCTAssertEqual(agent.cwd, "/tmp/work")
        XCTAssertEqual(snapshot.workspaces.first?.workspaceID, "w3Y")
        XCTAssertEqual(snapshot.paneIDs, ["w3Y:p12"])
    }

    func testDropsAgentWithoutPaneID() {
        let json: JSONObject = ["agents": [["agent": "claude"]]]

        let snapshot = HerdrClient.decodeSnapshot(json)

        XCTAssertTrue(snapshot.agents.isEmpty)
    }

    func testUnknownStatusMapsToUnknown() {
        let json: JSONObject = [
            "agents": [["pane_id": "p1", "agent_status": "brand-new-status"]],
        ]

        let snapshot = HerdrClient.decodeSnapshot(json)

        XCTAssertEqual(snapshot.agents.first?.status, .unknown)
    }

    func testEmptyOrMissingSectionsDecodeToEmpty() {
        let snapshot = HerdrClient.decodeSnapshot([:])

        XCTAssertTrue(snapshot.agents.isEmpty)
        XCTAssertTrue(snapshot.workspaces.isEmpty)
        XCTAssertTrue(snapshot.paneIDs.isEmpty)
    }

    // MARK: - Duplicate pane ids

    func testDuplicatePaneIDKeepsLastObservation() {
        let json: JSONObject = [
            "agents": [
                ["pane_id": "p1", "agent_status": "working"],
                ["pane_id": "p1", "agent_status": "blocked"],
            ],
        ]

        let agents = HerdrClient.dedupeByPaneID(HerdrClient.decodeSnapshot(json).agents)

        XCTAssertEqual(agents.map(\.paneID), ["p1"])
        XCTAssertEqual(agents.first?.status, .blocked)
    }

    func testDedupePreservesOrderOfDistinctAgents() {
        let json: JSONObject = [
            "agents": [
                ["pane_id": "p1", "agent_status": "working"],
                ["pane_id": "p2", "agent_status": "done"],
                ["pane_id": "p1", "agent_status": "blocked"],
                ["pane_id": "p3", "agent_status": "idle"],
            ],
        ]

        let agents = HerdrClient.dedupeByPaneID(HerdrClient.decodeSnapshot(json).agents)

        XCTAssertEqual(agents.map(\.paneID), ["p2", "p1", "p3"])
        XCTAssertEqual(agents.map(\.status), [.done, .blocked, .idle])
    }

    func testDedupeReturnsInputUnchangedWhenUnique() {
        let json: JSONObject = [
            "agents": [
                ["pane_id": "p1", "agent_status": "working"],
                ["pane_id": "p2", "agent_status": "done"],
            ],
        ]

        let agents = HerdrClient.dedupeByPaneID(HerdrClient.decodeSnapshot(json).agents)

        XCTAssertEqual(agents.map(\.paneID), ["p1", "p2"])
    }
}
