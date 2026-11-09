#if !canImport(DrillbitCore)
  import Testing
  @testable import Drillbit

  /// Bit's pick for the next level and the line that says how far along you are, by the level estimate's own rule.
  struct LevelPathTests {
    private func node(_ id: String, _ category: String, _ state: KnowledgeNode.State, reps: Int = 0) -> KnowledgeNode {
      KnowledgeNode(id: id, label: id, category: category, description: "About \(id).", reps: reps, state: state, evidence: nil)
    }

    @Test func aGapComesBeforeSomethingNew() {
      let nodes = [node("caching", "Traffic", .unexplored), node("transactions", "Data", .revisit, reps: 1)]
      #expect(LevelPath.choose(nodes: nodes, rated: []).0?.id == "transactions")
    }

    @Test func somethingNewComesFromTheAreaYouveTouchedLeast() {
      let nodes = [
        node("data-modeling", "Data", .strong, reps: 2), node("indexing", "Data", .unexplored),
        node("queues", "Async", .unexplored),
      ]
      let (pick, reason) = LevelPath.choose(nodes: nodes, rated: [])
      #expect(pick?.id == "queues")
      #expect(reason == "About queues.")
    }

    @Test func withNothingNewItsThePractisedConceptWithFewestReps() {
      let nodes = [node("caching", "Traffic", .practised, reps: 3), node("queues", "Async", .practised, reps: 1),
                   node("indexing", "Data", .strong, reps: 1)]
      #expect(LevelPath.choose(nodes: nodes, rated: []).0?.id == "queues")
    }

    @Test func progressSaysWhatTheEstimateNeeds() {
      let staff = (id: "staff", label: "Staff")
      #expect(LevelPath(level: staff, placing: false, held: 1, tried: 3, rated: 5, pick: nil, reason: nil).progressLine
        == "1 of 2 reps at Staff held up so far.")
      // Two held up but too few of the reps there: most of them need to.
      #expect(LevelPath(level: staff, placing: false, held: 2, tried: 5, rated: 6, pick: nil, reason: nil).progressLine
        == "2 of 5 reps at Staff held up. Most of them need to.")
      #expect(LevelPath(level: staff, placing: true, held: 0, tried: 0, rated: 2, pick: nil, reason: nil).progressLine
        == "1 more rep with real design calls and Bit places you.")
    }
  }
#endif
