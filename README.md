# Endpoints

![CI](https://github.com/velos/Endpoints/workflows/CI/badge.svg) ![Documentation](https://github.com/velos/Endpoints/workflows/Documentation/badge.svg)

Endpoints is a small library for creating statically and strongly-typed definitions of endpoints with paths, methods, inputs and outputs.

## Purpose

The purpose of Endpoints is to, in a type-safe way, define how to create a `URLRequest` from typed properties and, additionally, define how a response for the request should be handled. The library not only includes the ability to create these requests in a type-safe way, but also includes helpers to perform the requests using `URLSession`. Endpoints does not try to wrap the URL loading system to provide features on top of it like Alamofire. Instead, Endpoints focuses on defining endpoints and associated data to produce a request as a `URLRequest` object to be plugged into vanilla `URLSession`s. However, this library could be used in conjunction with Alamofire if desired.

## Getting Started

The basic process for defining an Endpoint starts with defining a value conforming to `Endpoint`. With the `Endpoint` protocol, you are encapsulating the definition of the endpoint, all the properties that are plugged into the definition and the types for parsing the response. Within the `Endpoint`, the `definition` static var serves as an immutable definition of the server's endpoint and how the variable pieces of the `Endpoint` should fit together when making the full request.

To get started, first create a type (struct or class) conforming to `Endpoint`. There are only two required elements to conform: defining the `Response` and creating the `Definition`.

`Endpoints` and `Definitions` do not contain base URLs so that these requests can be used on different environments. Environments are defined as conforming to the `EnvironmentType` and implement a `baseURL` as well as an optional `requestProcessor` which has a final hook before `URLRequest` creation to modify the `URLRequest` to attach authentication or signatures.

To find out more about the pieces of the `Endpoint`, check out [Defining a ResponseType](https://github.com/velos/Endpoints/wiki/DefiningResponseType) on the wiki.

## Examples

The most basic example of defining an Endpoint is creating a simple GET request. This means defining a type that conforms to `Endpoint` such as:

```Swift
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

This includes a `Response` associated type (can be typealiased to a more complex existing type) which defines how the response will come back from the request.

Then usage can employ the `URLSession` extensions:

#### Usage
```Swift
URLSession.shared.endpointPublisher(in: .production, with: MyEndpoint())
    .sink { completion in
        guard case .failure(let error) = completion else { return }
        // handle error
    } receiveValue: { (response: MyEndpoint.Response) in
        // handle MyEndpoint.Response
    }
    .store(in: &cancellables)
```

To browse more complex examples, make sure to check out the [Examples](https://github.com/velos/Endpoints/wiki/Examples) wiki page.
