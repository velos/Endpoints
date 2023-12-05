# Examples

### GET Request

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint())
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint(pathComponents: .init(userId: "42")))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### GET Request with ``Endpoint/HeaderValues``

#### Endpoint and Definition
```swift
extension Header {
    static let myCustomHeader = Header(name: "X-CUSTOM")
    static let myOtherCustomHeader = Header(name: "X-OTHER-CUSTOM")
    static let myHardCodedHeader = Header(name: "X-HARD-CODED")
}

struct MyEndpoint: Endpoint {
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint(headerValues: .init(headerString: "headerValue", headerInt: 42)))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

### POST Request with ``Enpdoint/Body``

#### Endpoint and Definition
```swift
struct MyEndpoint: Endpoint {
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint(body: .init(bodyName: "value")))
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint(parameters: .init(keyString: "value", keyInt: 42)))
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint(parameters: .init(keyString: "value", keyInt: 42)))
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
    static let definition: Definition<MyEndpoint> = Definition(
        method: .delete,
        path: "path/to/resource"
    )

    typealias Response = Void
}
```

#### Usage
```swift
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint())
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint())
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint(body: .init(bodyValue: "value")))
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint())
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
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint())
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
