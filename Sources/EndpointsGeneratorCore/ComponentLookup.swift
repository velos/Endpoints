#if OpenAPIGenerator
import EndpointsGeneratorConfig
import OpenAPIKit

struct Located<Value> {
    let value: Value
    let pointer: String
}

/// OpenAPIKit's String-keyed subscript uses Unicode canonical equivalence.
/// Wire references must match UTF-8 bytes, and diagnostics must retain the final
/// component's source pointer rather than the location of the referring object.
struct ComponentLookup {
    let components: OpenAPI.Components

    func resolve<Value: ComponentDictionaryLocatable>(
        _ input: Either<OpenAPI.Reference<Value>, Value>,
        at pointer: String
    ) throws -> Located<Value> {
        var current = input
        var location = pointer
        var visited: Set<[UInt8]> = []
        while case .a(let reference) = current {
            guard let name = reference.jsonReference.name,
                visited.insert(Array(name.utf8)).inserted
            else { throw NameError("Cannot resolve local component reference") }
            location = "/components/" + Value.openAPIComponentsKey + "/" + pointerPart(name)
            switch Value.openAPIComponentsKeyPath {
            case .a(let keyPath):
                guard
                    let value = components[keyPath: keyPath].first(where: {
                        wireEqual($0.key.rawValue, name)
                    })?.value
                else { throw NameError("Unknown component reference '\(name)'") }
                current = .b(value)
            case .b(let keyPath):
                guard
                    let value = components[keyPath: keyPath].first(where: {
                        wireEqual($0.key.rawValue, name)
                    })?.value
                else { throw NameError("Unknown component reference '\(name)'") }
                current = value
            }
        }
        guard case .b(let value) = current else {
            preconditionFailure("Reference resolution did not terminate")
        }
        return Located(value: value, pointer: location)
    }

    func schema(named name: String) throws -> JSONSchema {
        guard
            let schema = components.schemas.first(where: { wireEqual($0.key.rawValue, name) })?
                .value
        else { throw NameError("Unknown component reference '\(name)'") }
        return schema
    }

    func schema(_ input: JSONSchema) throws -> JSONSchema {
        var current = input
        var visited: Set<[UInt8]> = []
        while case .reference(let reference, _) = current.value {
            guard let name = reference.name, visited.insert(Array(name.utf8)).inserted
            else { throw NameError("Cannot resolve recursive component reference") }
            current = try schema(named: name)
        }
        return current
    }
}
#endif
