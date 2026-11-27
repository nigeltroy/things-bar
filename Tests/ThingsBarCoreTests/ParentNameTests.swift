import Testing
@testable import ThingsBarCore

/// The project/area under each to-do isn't repeated when it's what the panel lists.
struct ParentNameTests {
    let personal = ThingsSource(kind: .area, identifier: "A1", name: "personal")
    let trip = ThingsSource(kind: .project, identifier: "P1", name: "Japan trip")
    var catalog: SourceCatalog { SourceCatalog(projects: [trip], areas: [personal]) }

    @Test func hiddenWhenListingThatArea() {
        let item = TodoItem(id: "1", title: "buy luggage", areaID: "A1")
        #expect(catalog.parentName(for: item, listedFrom: personal) == nil)
    }

    @Test func hiddenWhenListingThatProject() {
        let item = TodoItem(id: "1", title: "book flights", projectID: "P1", areaID: "A1")
        #expect(catalog.parentName(for: item, listedFrom: trip) == nil)
    }

    @Test func projectInsideListedAreaStillShows() {
        let item = TodoItem(id: "1", title: "book flights", projectID: "P1", areaID: "A1")
        #expect(catalog.parentName(for: item, listedFrom: personal) == "Japan trip")
    }

    @Test func shownForListsAndTags() {
        let item = TodoItem(id: "1", title: "buy luggage", areaID: "A1")
        #expect(catalog.parentName(for: item, listedFrom: .today) == "personal")
        #expect(catalog.parentName(for: item, listedFrom: ThingsSource(kind: .tag, identifier: "errand", name: "errand")) == "personal")
    }

    @Test func shownWhenListingAnotherProject() {
        let item = TodoItem(id: "1", title: "pack", projectID: "P1")
        let other = ThingsSource(kind: .project, identifier: "P2", name: "Move")
        #expect(catalog.parentName(for: item, listedFrom: other) == "Japan trip")
    }

    @Test func unknownProjectFallsBackToArea() {
        let item = TodoItem(id: "1", title: "x", projectID: "gone", areaID: "A1")
        #expect(catalog.parentName(for: item, listedFrom: .today) == "personal")
        #expect(catalog.parentName(for: item, listedFrom: personal) == nil)
    }
}
