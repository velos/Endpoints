// endpoints-configuration-version: 1
import EndpointsGeneratorConfig

let petstoreConfiguration = EndpointsConfiguration(
    accessLevel: .public,
    parameterNamingStrategy: .custom { $0.camelCased }
)
