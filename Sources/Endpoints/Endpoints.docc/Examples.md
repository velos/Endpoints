# Examples

## Defining a Server

Before creating endpoints, you first need to define a server that conforms to ``ServerDefinition``. This replaces the old `EnvironmentType` approach and provides a more integrated way to manage environments.

### Basic Server Definition

```swift
import Endpoints
import Foundation

struct ApiServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        return [
            .local: URL(string: "https://local-api.example.com")!,
            .staging: URL(string: "https://staging-api.example.com")!,
            .production: URL(string: "https://api.example.com")!
        ]
    }

    static var defaultEnvironment: Environments { .production }
}
```

### Using GenericServer

For simple use cases, you can use the built-in ``GenericServer``:

```swift
let server = GenericServer(
    local: URL(string: "https://localhost:8080"),
    staging: URL(string: "https://staging-api.example.com"),
    production: URL(string: "https://api.example.com")
)
```

### Custom Environments

You can define custom environment types beyond the standard ``TypicalEnvironments``:

```swift
enum CustomEnvironments: String, CaseIterable, Sendable {
    case debug
    case testing
    case production
}

struct CustomServer: ServerDefinition {
    typealias Environments = CustomEnvironments
    
    var baseUrls: [Environments: URL] {
        return [
            .debug: URL(string: "https://debug-api.example.com")!,
            .testing: URL(string: "https://test-api.example.com")!,
            .production: URL(string: "https://api.example.com")!
        ]
    }

    static var defaultEnvironment: Environments { .debug }
    
    var requestProcessor: (URLRequest) -> URLRequest {
        return { request in
            var mutableRequest = request
            mutableRequest.setValue("Bearer token", forHTTPHeaderField: "Authorization")
            return mutableRequest
        }
    }
}
```

### Changing Environments

To switch environments at runtime, set the environment on the server type:

```swift
// Switch to staging environment
ApiServer.environment = .staging

// All subsequent requests will use the staging URL
```

---

## Endpoint Examples

### GET Request

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .get,
        path: "path/to/resource"
    )

    struct Response: Decodable {
        let resourceId: String
        let resourceName: String
    }
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### GET Request with ``Endpoint/PathComponents``

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .get,
        path: "user/\(path: \.userId)/resource"
    )

    struct Response: Decodable {
        let value: String
    }

    struct PathComponents {
        let userId: String
    }

    let pathComponents: PathComponents
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint(pathComponents: .init(userId: "42")))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### GET Request with ``Endpoint/HeaderComponents``

#### Endpoint and Definition
```swift
extension Header {
    static let myCustomHeader = Header(name: "X-CUSTOM")
    static let myOtherCustomHeader = Header(name: "X-OTHER-CUSTOM")
    static let myHardCodedHeader = Header(name: "X-HARD-CODED")
}

struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .get,
        path: "path/to/resource",
        headers: [
            .myCustomHeader: .field(path: \MyEndpoint.HeaderValues.headerString),
            .myOtherCustomHeader: .field(path: \MyEndpoint.HeaderValues.headerInt),
            .myHardCodedHeader: .fieldValue(value: "value")
        ]
    )

    struct Response: Decodable {
        let value: String
    }

    struct HeaderValues {
        let headerString: String
        let headerInt: Int
    }

    let headerValues: HeaderValues
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint(headerValues: .init(headerString: "headerValue", headerInt: 42)))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### POST Request with ``Endpoint/Body``

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .post,
        path: "path/to/resource"
    )

    struct Response: Decodable {
        let value: String
    }

    struct Body: Encodable {
        let bodyName: String
    }

    let body: Body
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint(body: .init(bodyName: "value")))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### POST Request with form ``Endpoint/ParameterComponents``

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .post,
        path: "path/to/resource",
        parameters: [
            .form("keyString", path: \MyEndpoint.ParameterComponents.keyString),
            .form("keyInt", path: \MyEndpoint.ParameterComponents.keyInt),
            .formValue("key", value: "hard-coded")
        ]
    )

    struct Response: Decodable {
        let resourceId: String
        let resourceName: String
    }

    struct Parameters {
        let keyString: String
        let keyInt: Int
    }

    let parameters: Parameters
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint(parameters: .init(keyString: "value", keyInt: 42)))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### POST Request with query ``Endpoint/ParameterComponents``

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .post,
        path: "path/to/resource",
        parameters: [
            .query("keyString", path: \MyEndpoint.ParameterComponents.keyString),
            .query("keyInt", path: \MyEndpoint.ParameterComponents.keyInt),
            .queryValue("key", value: "hard-coded")
        ]
    )

    struct Response: Decodable {
        let resourceId: String
        let resourceName: String
    }

    struct Parameters {
        let keyString: String
        let keyInt: Int
    }

    let parameters: Parameters
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint(parameters: .init(keyString: "value", keyInt: 42)))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

#### Output URL

```
https://production.mydomain.com/path/to/resource?keyString=value&keyInt=42&key=hard-coded
```

### DELETE Request with Void ``Endpoint/Response``

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .delete,
        path: "path/to/resource"
    )

    typealias Response = Void
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: Void) in
        // handle success with ignored response
    }
    .store(in: &cancellables)
```

### GET Request with custom ``Endpoint/ResponseDecoder``

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .get,
        path: "path/to/resource"
    )

    struct Response: Decodable {
        let resourceId: String
        let resourceName: String
    }

    static let responseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response and has been decoded
        // with the custom responseDecoder
    }
    .store(in: &cancellables)
```

### POST Request with custom ``Endpoint/BodyEncoder``

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .post,
        path: "path/to/resource"
    )

    struct Response: Decodable {
        let value: String
    }

    struct Body: Encodable {
        let bodyValue: String
    }

    let body: Body

    static let bodyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint(body: .init(bodyValue: "value")))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### GET Request with custom ``Endpoint/ErrorResponse``

#### Endpoint and Definition
```swift
struct ServerError: Decodable {
    let code: Int
    let message: String
}

struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .get,
        path: "path/to/resource"
    )

    typealias ErrorResponse = ServerError

    struct Response: Decodable {
        let responseValue: String
    }
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        switch error {
            case .errorResponse(let code, let error):
                // handle error, which is typed to ErrorResponse
            default:
                break
        }
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### GET Request with custom ``Endpoint/ErrorResponse`` and ``Endpoint/ErrorDecoder``

#### Endpoint and Definition
```swift
struct ServerError: Decodable {
    let code: Int
    let message: String
}

struct MyEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<MyEndpoint> = Definition(
        method: .get,
        path: "path/to/resource"
    )

    typealias ErrorResponse = ServerError

    struct Response: Decodable {
        let responseValue: String
    }

    static let errorDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(with: MyEndpoint())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        switch error {
            case .errorResponse(let code, let error):
                // handle error, which is typed to ErrorResponse and
                // has been decoded with the custom errorDecoder
            default:
                break
        }
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### Async/Await Usage

All endpoints can also be used with Swift's async/await:

```swift
do {
    let response = try await URLSession.shared.response(with: MyEndpoint())
    // handle response
} catch {
    // handle error
}
```

### Multipart Form Upload

For file uploads using multipart/form-data:

```swift
struct UploadEndpoint: Endpoint {
    typealias Server = ApiServer
    
    static let definition: Definition<UploadEndpoint> = Definition(
        method: .post,
        path: "upload"
    )

    struct Response: Decodable {
        let fileId: String
    }

    struct Body: MultipartFormEncodable {
        let file: MultipartFile
        let description: String
    }

    let body: Body
}

// Usage
let file = MultipartFile(
    filename: "photo.jpg",
    contentType: "image/jpeg",
    data: imageData
)

let endpoint = UploadEndpoint(body: .init(
    file: file,
    description: "Profile photo"
))

let response = try await URLSession.shared.response(with: endpoint)
```
