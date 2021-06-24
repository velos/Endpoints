## Defining a ResponseType

### `Response` (associatedtype, required)

The `Response` is an associated type which defines the response from the server. Note that this is just type information which helpers, such as the built-in `URLSession` extensions, can use to know how to handle particular types. For instance, if this type conforms to `Decodable`, then a JSON decoder is used on the data coming from the server. If it's typealiased to `Void`, then the extension can know to ignore the response. If it's `Data`, then it can deliver the response data unmodified.

### `ErrorResponse` (associatedtype, optional, defaults to `EmptyCodable`)

An `ErrorResponse` type can be associated to define what value conforming to `Decodable` to use when parsing an error response from the server. This can be useful if your server returns a different JSON structure when there's an error versus a success. Often in a project, this can be defined globally and `typealias` can be used to associate this global type on all `Endpoint`s.

### `Body` (associatedtype, optional, defaults to `EmptyCodable`)

When POST-ing JSON to your server, a `Body` conforming to `Encodable` can be associated. This value will be encoded as JSON into the body of the HTTP request.

### `PathComponents` (associatedtype, defaults to `Void`)

If a `PathComponents` type is associated, properties of that type can be utilized in the `path` of the `Endpoint` using a path string interpolation syntax:

```Swift
struct DeleteEndpoint: Endpoint {
    static let definition: Definition<DeleteEndpoint> = Definition(
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

With this enum, either hard-coded values can be injected into the `Endpoint` (with `.formValue(_:value:)` or `.queryValue(_:value:)`) or key paths can define which reference properties in the `Parameters` associated type to define a form or query parameter that is needed at the time of the request.

### `HeaderValues` (associatedtype, defaults to `Void`)

Custom headers can be included in your `Definition` by passing a dictionary of `[Header: HeaderField]` to the headers property. The `HeaderField` enum values can include references by key paths to `HeaderComponent`s or to hard-coded strings:

```Swift
static let definition: Definition<UserEndpoint> = Definition(
    method: .get,
    path: "/request",
    headers: [
        "X-TYPE": HeaderField.field(path: \UserEndpoint.HeaderValues.type),
        "X-VALUE": .fieldValue(value: "value"),
        .keepAlive: .fieldValue(value: "timeout=5, max=1000")
    ]
)
```

Custom keys in the headers dictionary can be defined ad-hoc using a String, or by extending the encapsulating type `Header`. Basic named headers, such as `.keepAlive`, `.accept`, etc., are already defined as part of the library.

### `BodyEncoder` (associatedtype, defaults to `JSONEncoder`)

This, coupled with the `bodyEncoder` property, can define custom encoders for the associated `Body` type when turning it into `Data` attached to the request. For instance, this can be customizations of the date encoding strategy or even completely different encoders for XML or other data formats.

### `ResponseDecoder` (associatedtype, defaults to `JSONEncoder`)

Similar to custom body encoding, the `ResponseDecoder` with the `responseDecoder` property can customize the decoder used for parsing responses from the server.

### `ErrorDecoder` (associatedtype, defaults to `JSONDecoder`)

Similar to `ResponseDecoder`, this allows customization of the decoder used when errors are encountered and parsed using the `ErrorResponse` type.

### `definition` (static var, required)

The `definition` static var defines how all the pieces defined in the `Endpoint` go together. Creating a `Definition` is usually the last step, since it requires all the properties of the `Endpoint` defined in order to put them together.

A `Definition` is a generic type with the type parameter conforming to `Endpoint`, or equivalently `Self` since the static let is defined as part of the `Endpoint` protocol.
