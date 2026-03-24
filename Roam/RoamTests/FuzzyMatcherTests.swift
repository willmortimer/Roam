import Testing
@testable import Roam

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {

    @Test("Empty query matches everything with score 0")
    func emptyQuery() {
        #expect(FuzzyMatcher.score(query: "", target: "anything") == 0)
    }

    @Test("Exact match scores higher than partial")
    func exactMatch() {
        let exact = FuzzyMatcher.score(query: "git status", target: "git status")
        let partial = FuzzyMatcher.score(query: "gst", target: "git status")
        #expect(exact != nil)
        #expect(partial != nil)
        #expect(exact! > partial!)
    }

    @Test("No match returns nil")
    func noMatch() {
        #expect(FuzzyMatcher.score(query: "xyz", target: "abc") == nil)
    }

    @Test("Case insensitive matching")
    func caseInsensitive() {
        let score = FuzzyMatcher.score(query: "GIT", target: "git status")
        #expect(score != nil)
    }

    @Test("Word boundary bonus")
    func wordBoundary() {
        // "gs" matching "git status" should get boundary bonus on 's'
        let withBoundary = FuzzyMatcher.score(query: "gs", target: "git status")
        // "gs" matching "gist" should not get boundary bonus on 's'
        let withoutBoundary = FuzzyMatcher.score(query: "gs", target: "gist")
        #expect(withBoundary != nil)
        #expect(withoutBoundary != nil)
        #expect(withBoundary! > withoutBoundary!)
    }

    @Test("Consecutive match bonus")
    func consecutiveBonus() {
        let consecutive = FuzzyMatcher.score(query: "git", target: "git push")
        let scattered = FuzzyMatcher.score(query: "git", target: "go into things")
        #expect(consecutive != nil)
        #expect(scattered != nil)
        #expect(consecutive! > scattered!)
    }

    @Test("Query longer than target returns nil")
    func queryLongerThanTarget() {
        #expect(FuzzyMatcher.score(query: "longquery", target: "short") == nil)
    }

    @Test("Single character match")
    func singleChar() {
        let score = FuzzyMatcher.score(query: "s", target: "Settings")
        #expect(score != nil)
        #expect(score! > 0)
    }
}
