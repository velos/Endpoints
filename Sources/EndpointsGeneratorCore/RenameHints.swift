#if OpenAPIGenerator
import EndpointsGeneratorConfig

/// Copyable Swift spellings for original identities and configuration rename hints.
func operationSwift(_ operation: OperationID) -> String {
    switch operation {
    case .id(let name): return swiftLiteral(name)
    case .route(let method, let path):
        return ".route(method: .\(method.rawValue), path: \(swiftLiteral(path)))"
    }
}
func typeSwift(_ type: TypeID) -> String {
    switch type {
    case .component(let name): return swiftLiteral(name)
    case .inline(let origin):
        let value: String
        switch origin {
        case .property(let name, let owner):
            value = ".property(\(swiftLiteral(name)), in: \(typeSwift(owner)))"
        case .items(let owner): value = ".items(of: \(typeSwift(owner)))"
        case .parameter(let name, let location, let operation):
            value =
                ".parameter(\(swiftLiteral(name)), in: .\(location.rawValue), of: \(operationSwift(operation)))"
        case .body(let operation): value = ".body(\(operationSwift(operation)))"
        case .response(let operation, let status):
            value = ".response(\(operationSwift(operation)), status: \(swiftLiteral(status)))"
        case .errorResponse(let operation, let status):
            value =
                ".errorResponse(\(operationSwift(operation)), status: \(swiftLiteral(status)))"
        }
        return ".inline(\(value))"
    }
}
package func targetSwift(_ target: NameTarget) -> String {
    switch target {
    case .type(let type): return ".type(\(typeSwift(type)))"
    case .property(let name, let owner):
        return ".property(\(swiftLiteral(name)), in: \(typeSwift(owner)))"
    case .enumCase(let name, let owner):
        return ".enumCase(\(swiftLiteral(name)), in: \(typeSwift(owner)))"
    case .parameter(let name, let location, let operation):
        return
            ".parameter(\(swiftLiteral(name)), in: .\(location.rawValue), of: \(operationSwift(operation)))"
    case .operation(let operation): return ".operation(\(operationSwift(operation)))"
    case .environment(let name): return ".environment(\(swiftLiteral(name)))"
    }
}
func renameHint(_ target: NameTarget) -> String {
    return "renames: [\(targetSwift(target)): \"NewName\"]"
}
#endif
