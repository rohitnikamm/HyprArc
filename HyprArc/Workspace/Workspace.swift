import CoreGraphics

/// A single virtual workspace with its own tiling engine and window set.
/// Each workspace maintains independent layout state.
struct Workspace {
    let id: Int
    var engine: any TilingEngine
    var windowIDs: Set<WindowID> = []
    var floatingWindowIDs: Set<WindowID> = []

    init(id: Int, engine: any TilingEngine = DwindleLayout()) {
        self.id = id
        self.engine = engine
    }

    /// All windows owned by this workspace (tiled + floating).
    var allWindowIDs: Set<WindowID> {
        windowIDs.union(floatingWindowIDs)
    }
}
