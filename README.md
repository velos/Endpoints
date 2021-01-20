# Endpoints

![CI](https://github.com/velos/Endpoints/workflows/CI/badge.svg) ![Documentation](https://github.com/velos/Endpoints/workflows/Documentation/badge.svg)

Endpoints is a small library for creating statically and strongly-typed definitions of endpoint with paths, methods, inputs and outputs.

## Purpose

The purpose of Endpoints is to, in a type-safe way, define how to create a `URLRequest` from typed properties and, additionally, define how a response for the request should be handled. The library not only includes the ability to create these requests in a type-safe way, but also includes helpers to perform the requests using `URLSession`. Endpoints does not try to wrap the URL loading system to provide features on top of it like Alamofire. Instead, Endpoints focuses on defining requests and converting those requests into `URLRequest` objects to be plugged into vanilla `URLSession`s. However, this library could be used in conjunction with Alamofire if desired.

## Overview of Defining an Endpoint

The basic process for defining an Endpoint starts with defining a value conforming to `RequestType`. With the `RequestType` protocol, you are encapsulating all the properties that are needed for making a request and the types for parsing the response. Within the `RequestType`, the `endpoint` static var serves as an immutable definition of the server's endpoint and how the variable pieces of the `RequestType` should fit together when making the full request.

To get started, first create a type (struct or class) conforming to `RequestType`. There are only two required elements to conform: defining the `Response` and creating the `Endpoint`.

### `Response` (associatedtype, required)

The `Response` is an associated type which defines the response from the server. Note that this is just type information which helpers, such as the built-in `URLSession` extensions, can use to know how to handle particular types. For instance, if this type conforms to `Decodable`, then a JSON decoder is used on the data coming from the server. If it's typealiased to `Void`, then the extension can know to ignore the response. If it's `Data`, then it can deliver the response data unmodified.

### `ErrorResponse` (associatedtype, optional, defaults to `EmptyResponse`)

An `ErrorResponse` type can be associated to define what value conforming to `Decodable` to use when parsing an error response from the server. This can be useful if your server returns a different JSON structure when there's an error versus a success. Often in a project, this can be defined globally and `typealias` can be used to associate this global type on all `RequestType`s.

### `Body` (associatedtype, optional, defaults to `EmptyResponse`)

When POST-ing JSON to your server, a `Body` conforming to `Encodable` can be associated. This value will be encoded as JSON into the body of the HTTP request.

### `PathComponents` (associatedtype, defaults to `Void`)

If a `PathComponents` type is associated, properties of that type can be utilized in the `path` of the `Endpoint` using a path string interpolation syntax:

```Swift
struct DeleteRequest: RequestType {
    static let endpoint: Endpoint<DeleteRequest> = Endpoint(
        method: .delete,
        path: "calendar/v3/calendars/\(path: \.calendarId)/events\(path: \.eventId)"
    )

    typealias Response = Void

    struct PathComponents {
        let calendarId: String
        let eventId: String
    }

    let pathComponents: PathComponents
}
```

### `Parameters` (associatedtype, defaults to `Void`)

A `Parameters` type, in a similar way to `PathComponents`, holds properties that can be referenced in the `Endpoint` as `Parameter<Parameters>` in order to define form parameters used in the body or query parameters attached to the URL. The enum type is defined as:

```Swift
public enum Parameter<T> {
    case form(String, path: PartialKeyPath<T>)
    case formValue(String, value: PathRepresentable)
    case query(String, path: PartialKeyPath<T>)
    case queryValue(String, value: PathRepresentable)
}
```

With this enum, either hard-coded values can be injected into the `Endpoint` (with `.formValue(_:value:)` or `.queryValue(_:value:)`) or key paths can define which properties in the `Parameters` associated type are pulled used for the form body or the query parameters.

### `HeaderValues` (associatedtype, defaults to `Void`)

Custom headers can be included in your `Endpoint` definition by associating a type with `HeaderValues` in your `RequestType`. These properties can be referenced by key paths in the `Endpoint` definition:

```Swift
static let endpoint: Endpoint<UserRequest> = Endpoint(
    method: .get,
    path: "/request",
    headers: [
        "X-TYPE": HeaderField.field(path: \UserRequest.HeaderValues.type),
        "X-VALUE": .fieldValue(value: "value"),
        .keepAlive: .fieldValue(value: "timeout=5, max=1000")
    ]
)
```

Custom keys in the headers dictionary can be defined ad-hoc using a String, or by extending an encapsulating type `Headers`. Basic named headers, such as `.keepAlive`, `.accept`, etc., are already defined as part of the library.

### `BodyEncoder` (associatedtype, defaults to `JSONEncoder`)

This, coupled with the `bodyEncoder` property, can define custom encoders for the associated `Body` type when turning it into `Data` attached to the request. For instance, this can be customizations of the date encoding strategy or even completely different encoders for XML or other data formats.

### `ResponseDecoder` (associatedtype, defaults to `JSONEncoder`)

Similar to custom body encoding, the `ResponseDecoder` with the `responseDecoder` property can customize the decoder used for parsing responses from the server.

### `ErrorDecoder` (associatedtype, defaults to `JSONDecoder`)

Similar to `ResponseDecoder`, this allows customization of the decoder used when errors are encountered and parsed using the `ErrorResponse` type.

### `endpoint` (static var, required)

The `Endpoint` static var defines how all the pieces defined in the `RequestType` go together. It's usually the last step, since it requires all the properties of `RequestType` in order to put them together.

An `Endpoint` is generic type with the type parameter conforming to `RequestType`, or equivalently `Self` since the static let is defined as part of the `RequestType` protocol.

## Examples

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

## OTHER
After creating this definition of what's contained in a request, how to parse the response and what details are needed to make that request with the server, you'll be plugging in those variable pieces in order to generate a `URLRequest` which you can easily plug into the existing `URLSession` system.

1. Create a struct or class conforming to `RequestType`. In order to conform to `RequestType`, you must define a `Response` associated type as well as an `endpoint` property. There are other