# Examples

Define servers and endpoints for common request shapes.

## Servers

A ``ServerDefinition`` lists a base URL for each environment and names the default:

```swift
struct ApiServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        [
            .local: URL(string: "https://local-api.example.com")!,
            .staging: URL(string: "https://staging-api.example.com")!,
            .production: URL(string: "https://api.example.com")!
        ]
    }

    static var defaultEnvironment: Environments { .production }
}
```

### Custom environments

`Environments` defaults to ``TypicalEnvironments``. Any `Hashable & Sendable` type works:

```swift
enum Region: Hashable, Sendable {
    case us
    case eu
}

struct RegionalServer: ServerDefinition {
    typealias Environments = Region

    var baseUrls: [Environments: URL] {
        [
            .us: URL(string: "https://us.api.example.com")!,
            .eu: URL(string: "https://eu.api.example.com")!
        ]
    }

    static var defaultEnvironment: Environments { .us }
}
```

### Choosing an environment

Each request takes an `environment:` argument, which defaults to the server's ``ServerDefinition/defaultEnvironment``:

```swift
let response = try await URLSession.shared.response(with: MyEndpoint(), environment: .staging)
let request = try MyEndpoint().urlRequest(in: .staging)
```

The environment belongs to the request, not to global state, so concurrent requests can use different environments.

### Processing requests

``ServerDefinition/requestProcessor`` runs synchronously on every request after it is built. Use it for static changes:

```swift
struct ApiServer: ServerDefinition {
    // baseUrls and defaultEnvironment as above

    var requestProcessor: @Sendable (URLRequest) -> URLRequest {
        { request in
            var request = request
            request.setValue(AppInfo.buildNumber, forHTTPHeaderField: "X-Client-Build")
            return request
        }
    }
}
```

For credentials, use ``ServerDefinition/auth`` instead. See <doc:Authentication>.

### Using GenericServer

An endpoint that doesn't name a server uses ``GenericServer``. Pass a configured instance to its ``Definition``:

```swift
struct StatusEndpoint: Endpoint {
    static let definition: Definition<StatusEndpoint> = Definition(
        server: GenericServer(baseUrl: URL(string: "https://status.example.com")!),
        method: .get,
        path: "status"
    )

    struct Response: Decodable {
        let healthy: Bool
    }
}
```

A `GenericServer()` with no URLs fails every request with ``EndpointError/misconfiguredServer(server:)``.

## Endpoints

Each example shows the endpoint and a call to it. Every example works with the Combine method `endpointPublisher(with:)` too.

### GET with a decoded response

```swift
struct ArticlesEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<ArticlesEndpoint> = Definition(
        method: .get,
        path: "articles"
    )

    struct Response: Decodable {
        let articles: [Article]
    }
}

let response = try await URLSession.shared.response(with: ArticlesEndpoint())
```

### Path components

Interpolate key paths into the path with `\(path:)`. Slashes are added between components as needed:

```swift
struct EventEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<EventEndpoint> = Definition(
        method: .get,
        path: "calendars/\(path: \.calendarId)/events/\(path: \.eventId)"
    )

    struct Response: Decodable {
        let title: String
    }

    struct PathComponents {
        let calendarId: String
        let eventId: Int
    }

    let pathComponents: PathComponents
}

let event = try await URLSession.shared.response(
    with: EventEndpoint(pathComponents: .init(calendarId: "work", eventId: 42))
)
```

### Query parameters

`.query` reads a value from ``Endpoint/ParameterComponents``, and `.queryValue` sends a fixed value. `nil` values are left out:

```swift
struct SearchEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<SearchEndpoint> = Definition(
        method: .get,
        path: "search",
        parameters: [
            .query("q", path: \.query),
            .query("page", path: \.page),
            .queryValue("format", value: "compact")
        ]
    )

    struct Response: Decodable {
        let results: [String]
    }

    struct ParameterComponents {
        let query: String
        let page: Int?
    }

    let parameterComponents: ParameterComponents
}

// https://api.example.com/search?q=swift&format=compact
let results = try await URLSession.shared.response(
    with: SearchEndpoint(parameterComponents: .init(query: "swift", page: nil))
)
```

Supported value types are `String`, `Int`, `Double`, `Bool`, `Date` (ISO 8601), `TimeZone`, and optionals of these. Conform other types to ``ParameterRepresentable``.

To control percent-encoding, set ``Endpoint/queryEncodingStrategy``. This one also encodes `+`, which some servers read as a space:

```swift
static var queryEncodingStrategy: QueryEncodingStrategy {
    .custom { item in
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+")
        return (item.name, item.value?.addingPercentEncoding(withAllowedCharacters: allowed))
    }
}
```

### Form parameters

`.form` and `.formValue` send an `application/x-www-form-urlencoded` body:

```swift
struct TokenEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<TokenEndpoint> = Definition(
        method: .post,
        path: "oauth/token",
        parameters: [
            .form("username", path: \.username),
            .form("password", path: \.password),
            .formValue("grant_type", value: "password")
        ]
    )

    struct Response: Decodable {
        let accessToken: String
    }

    struct ParameterComponents {
        let username: String
        let password: String
    }

    let parameterComponents: ParameterComponents
}
```

### Headers

`.field` reads a value from ``Endpoint/HeaderComponents``, and `.fieldValue` sends a fixed value. Define your own ``Header`` names by extending the type, or use a string literal:

```swift
extension Header {
    static let requestId = Header(name: "X-Request-ID")
}

struct ReportEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<ReportEndpoint> = Definition(
        method: .get,
        path: "report",
        headers: [
            .requestId: .field(path: \.requestId),
            .accept: .fieldValue(value: "application/json"),
            "X-Client": .fieldValue(value: "ios")
        ]
    )

    struct Response: Decodable {
        let total: Int
    }

    struct HeaderComponents {
        let requestId: String
    }

    let headerComponents: HeaderComponents
}
```

### JSON body

A ``Endpoint/Body`` is encoded with `JSONEncoder`, and `Content-Type` is set to `application/json`:

```swift
struct CreateArticleEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<CreateArticleEndpoint> = Definition(
        method: .post,
        path: "articles"
    )

    struct Body: Encodable {
        let title: String
        let text: String
    }

    struct Response: Decodable {
        let id: String
    }

    let body: Body
}

let created = try await URLSession.shared.response(
    with: CreateArticleEndpoint(body: .init(title: "Hello", text: "..."))
)
```

### Multipart upload

Set ``Endpoint/bodyEncoder`` to ``MultipartFormEncoder``. Each property of the body becomes a part. Use ``MultipartFormFile`` for files and ``MultipartFormJSON`` for a part that holds JSON:

```swift
struct UploadEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<UploadEndpoint> = Definition(
        method: .post,
        path: "uploads"
    )

    struct Body: Encodable {
        let caption: String
        let photo: MultipartFormFile
        let metadata: MultipartFormJSON<Metadata>
    }

    struct Metadata: Encodable, Sendable {
        let albumId: String
    }

    struct Response: Decodable {
        let fileId: String
    }

    static var bodyEncoder: MultipartFormEncoder { MultipartFormEncoder() }

    let body: Body
}

let upload = UploadEndpoint(body: .init(
    caption: "Profile photo",
    photo: MultipartFormFile(data: imageData, fileName: "photo.jpg", contentType: "image/jpeg"),
    metadata: MultipartFormJSON(.init(albumId: "a1"))
))
let response = try await URLSession.shared.response(with: upload)
```

### Empty or raw responses

Use `Void` when the response has no body you need, such as a 204:

```swift
struct DeleteArticleEndpoint: Endpoint {
    typealias Server = ApiServer

    static let definition: Definition<DeleteArticleEndpoint> = Definition(
        method: .delete,
        path: "articles/\(path: \.id)"
    )

    typealias Response = Void

    struct PathComponents {
        let id: String
    }

    let pathComponents: PathComponents
}

try await URLSession.shared.response(with: DeleteArticleEndpoint(pathComponents: .init(id: "a1")))
```

Use `Data` to receive the body without decoding it.

### Custom decoders and encoders

Override ``Endpoint/responseDecoder``, ``Endpoint/errorDecoder``, or ``Endpoint/bodyEncoder``:

```swift
struct ProfileEndpoint: Endpoint {
    // ...

    static let responseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static let bodyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}
```

Any type that conforms to ``DecoderType`` or ``EncoderType`` works.

### Typed error responses

When a server returns a structured body for errors, set ``Endpoint/ErrorResponse``. Non-2xx responses are decoded as that type and thrown as ``EndpointTaskError/errorResponse(httpResponse:response:)``:

```swift
struct ServerError: Decodable, Sendable {
    let code: Int
    let message: String
}

struct ArticleEndpoint: Endpoint {
    typealias Server = ApiServer
    typealias ErrorResponse = ServerError
    // ...
}

do {
    let article = try await URLSession.shared.response(with: ArticleEndpoint())
} catch {
    // error is ArticleEndpoint.TaskError
    if case .errorResponse(let httpResponse, let serverError) = error {
        print(httpResponse.statusCode, serverError.message)
    }
}
```

If many endpoints share one error type, define a `typealias` once and reuse it.

### Completion handlers

For unauthenticated endpoints, `endpointTask(with:completion:)` creates a data task without starting it:

```swift
let task = try URLSession.shared.endpointTask(with: ArticlesEndpoint()) { result in
    switch result {
    case .success(let response):
        // handle response
    case .failure(let error):
        // handle ArticlesEndpoint.TaskError
    }
}
task.resume()
```

It throws if the request can't be built, and it doesn't accept authenticated endpoints. Use `response(with:)` or `endpointPublisher(with:)` for those.
