# ``Endpoints``

Endpoints is a small library for creating statically and strongly-typed definitions of endpoints with paths, methods, inputs and outputs.

## Overview

The purpose of Endpoints is to, in a type-safe way, define how to create a `URLRequest` from typed properties and, additionally, define how a response for the request should be handled. The library not only includes the ability to create these requests in a type-safe way, but also includes helpers to perform the requests using ``Foundation/URLSession``. Endpoints does not try to wrap the URL loading system to provide features on top of it like Alamofire. Instead, Endpoints focuses on defining endpoints and associated data to produce a request as a URLRequest object to be plugged into vanilla ``Foundation/URLSession``s. However, this library could be used in conjunction with Alamofire if desired.

## Topics

### Essentials

- ``Endpoint``
- ``ServerDefinition``
- ``Definition``
- <doc:Examples>

### Server Configuration

- ``ServerDefinition``
- ``GenericServer``
- ``TypicalEnvironments``

### Testing and Mocking

- <doc:Mocking>
- ``EndpointsMocking``
- ``withMock(_:_:test:)``
- ``MockContinuation``
- ``MockAction``

### Making Requests

#### Combine

- ``Foundation/URLSession``
- ``Endpoint/Response``
