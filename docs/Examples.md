# Examples

### GET Request

#### Request Definition
```Swift
struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```

### GET Request with `PathComponents`

#### Request Definition
```Swift
struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest(pathComponents: .init(userId: "42")))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```

### GET Request with `HeaderValues`

#### Request Definition
```Swift
extension Headers {
    static let myCustomHeader = Headers(name: "X-CUSTOM")
    static let myOtherCustomHeader = Headers(name: "X-OTHER-CUSTOM")
    static let myHardCodedHeader = Headers(name: "X-HARD-CODED")
}

struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
        method: .get,
        path: "path/to/resource",
        headers: [
            .myCustomHeader: .field(path: \MyRequest.HeaderValues.headerString),
            .myOtherCustomHeader: .field(path: \MyRequest.HeaderValues.headerInt),
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest(headerValues: .init(headerString: "headerValue", headerInt: 42)))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```

### POST Request with `Body`

#### Request Definition
```Swift
struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest(body: .init(bodyName: "value")))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```

### POST Request with form `Parameters`

#### Request Definition
```Swift
struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
        method: .post,
        path: "path/to/resource",
        parameters: [
            .form("keyString", path: \MyRequest.Parameters.keyString),
            .form("keyInt", path: \MyRequest.Parameters.keyInt),
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest(parameters: .init(keyString: "value", keyInt: 42)))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```

### POST Request with query `Parameters`

#### Request Definition
```Swift
struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
        method: .post,
        path: "path/to/resource",
        parameters: [
            .query("keyString", path: \MyRequest.Parameters.keyString),
            .query("keyInt", path: \MyRequest.Parameters.keyInt),
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest(parameters: .init(keyString: "value", keyInt: 42)))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```

#### Output URL

```
https://production.mydomain.com/path/to/resource?keyString=value&keyInt=42&key=hard-coded
```

### DELETE Request with Void `Response`

#### Request Definition
```Swift
struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
        method: .delete,
        path: "path/to/resource"
    )

    typealias Response = Void
}
```

#### Usage
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: Void) in
        // handle success with ignored response
    }
    .store(in: &cancellables)
```

### GET Request with custom `ResponseDecoder`

#### Request Definition
```Swift
struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response and has been decoded
        // with the custom responseDecoder
    }
    .store(in: &cancellables)
```

### POST Request with custom `BodyEncoder`

#### Request Definition
```Swift
struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest(body: .init(bodyValue: "value")))
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```

### GET Request with custom `ErrorResponse`

#### Request Definition
```Swift

struct ServerError: Decodable {
    let code: Int
    let message: String
}

struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        switch error {
            case .errorResponse(let code, let error):
                // handle error, which is typed to ErrorResponse
            default:
                break
        }
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```

### GET Request with custom `ErrorResponse` and `ErrorDecoder`

#### Request Definition
```Swift
struct ServerError: Decodable {
    let code: Int
    let message: String
}

struct MyRequest: RequestType {
    static let endpoint: Endpoint<MyRequest> = Endpoint(
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
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyRequest())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        switch error {
            case .errorResponse(let code, let error):
                // handle error, which is typed to ErrorResponse and
                // has been decoded with the custom errorDecoder
            default:
                break
        }
    } receiveValue: { (response: MyRequest.Response) in
        // handle MyRequest.Response
    }
    .store(in: &cancellables)
```