#if OpenAPIGenerator
import OpenAPIKit

/// Strongly connected components of the schema reference graph. Edges include
/// references inside arrays and inline compositions, without expanding targets.
/// The SCCs are also the boundary for future recursive-schema boxing.
struct ComponentGraph {
    struct Vertex {
        let name: String
        let references: [Int]
    }

    let vertices: [Vertex]
    let stronglyConnectedComponents: [[Int]]
    private let recursiveNames: Set<[UInt8]>

    init(schemas: OpenAPI.ComponentDictionary<JSONSchema>) {
        let entries = Array(schemas)
        let indices = Dictionary(
            uniqueKeysWithValues: entries.enumerated().map {
                (Array($0.element.key.rawValue.utf8), $0.offset)
            })
        func references(in schema: JSONSchema) -> [Int] {
            switch schema.value {
            case .reference(let reference, _):
                return reference.name.flatMap { indices[Array($0.utf8)] }.map { [$0] } ?? []
            case .object(_, let object):
                var result = object.properties.flatMap { references(in: $0.value) }
                if case .b(let additional)? = object.additionalProperties {
                    result += references(in: additional)
                }
                return result
            case .array(_, let array):
                return array.items.map { references(in: $0) } ?? []
            case .one(let members, _), .any(let members, _), .all(let members, _):
                return members.flatMap { references(in: $0) }
            case .not(let member, _): return references(in: member)
            default: return []
            }
        }
        let vertices = entries.map {
            Vertex(name: $0.key.rawValue, references: references(in: $0.value))
        }
        self.vertices = vertices

        // Tarjan: each vertex and edge is visited once. Dictionaries above are
        // lookup-only; traversal follows the document's ordered component array.
        var nextIndex = 0
        var discovery = [Int?](repeating: nil, count: vertices.count)
        var lowLink = [Int](repeating: 0, count: vertices.count)
        var stack: [Int] = []
        var onStack = [Bool](repeating: false, count: vertices.count)
        var components: [[Int]] = []
        func connect(_ vertex: Int) {
            discovery[vertex] = nextIndex
            lowLink[vertex] = nextIndex
            nextIndex += 1
            stack.append(vertex)
            onStack[vertex] = true
            for target in vertices[vertex].references {
                if discovery[target] == nil {
                    connect(target)
                    lowLink[vertex] = min(lowLink[vertex], lowLink[target])
                } else if onStack[target], let targetIndex = discovery[target] {
                    lowLink[vertex] = min(lowLink[vertex], targetIndex)
                }
            }
            if lowLink[vertex] == discovery[vertex] {
                var component: [Int] = []
                while let member = stack.popLast() {
                    onStack[member] = false
                    component.append(member)
                    if member == vertex { break }
                }
                components.append(component)
            }
        }
        for vertex in vertices.indices where discovery[vertex] == nil { connect(vertex) }
        stronglyConnectedComponents = components
        let recursiveVertices = components.filter { component in
            component.count > 1 || component.contains { vertices[$0].references.contains($0) }
        }.flatMap { $0 }
        recursiveNames = Set(recursiveVertices.map { Array(vertices[$0].name.utf8) })
    }

    func isRecursive(_ name: String) -> Bool {
        recursiveNames.contains(Array(name.utf8))
    }
}
#endif
