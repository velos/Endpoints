# Ordering audit (OpenAPIKit 6.4.0, Yams 6.2.2)

The IR contains only value types and arrays. Its renderer never enumerates a
Dictionary or Set. String comparisons use UTF-8 lexicographic ordering, not
Unicode collation or locale. Parser pins are part of generator version 0.1.0.

| Source | Handling |
| --- | --- |
| Document paths and path-item operations | OrderedDictionary / fixed builtin method list; endpoints sorted by final Swift name before rendering |
| Component schemas | OrderedDictionary; names allocated without suffixing; declarations sorted by Swift name |
| Schema properties | OrderedDictionary, including Compat30To31's order-preserving mapValues; property, initializer, CodingKeys, coding-call order retained |
| Required names | Array interpreted by parser as property metadata; never used as declaration order |
| Inline types | Collected arrays sorted by Swift name within each scope; inline items of namespace-level array aliases are lifted to sibling declarations and collision-checked |
| String/integer enum values | allowedValues array; scalar wire values; order retained for cases and knownValues |
| Servers and variables | Ordered arrays / OrderedDictionary; environment cases retain spec order and the first server determines the default; variables substituted in document order |
| Config environments and renames | Yams node mapping converted to arrays; environments and rename keys sorted by UTF-8 name |
| Parameters | Path-item array first, overridden identities removed, operation array appended; each component category retains this order |
| Header entries | Array sorted by original wire header name |
| Content maps | OrderedDictionary; first exact application/json, else first +json, else first entry; document order breaks ties |
| Response maps | OrderedDictionary; category members retain authored order; dispatch sorts exact codes before ranges before default, with authored indices breaking ties; inline OptionN payloads use category member indices |
| SecurityRequirement dictionaries | First document requirement selected in array order; its dictionary keys sorted by UTF-8 for the auth example; per-scheme docs sorted by component key |
| vendorExtensions / object AnyCodable values | Never read or enumerated |
| Document.allTags Set | Never read; operation.tags arrays only |
| NameAllocator reserved Set | Membership only; assigned names held in arrays; collisions are errors; path helper _endpointPath is reserved in PathComponents |
| Reference traversal | Tarjan SCCs computed once over ordered component/inline reference edges; recursion checks are membership lookups. ComponentLookup matches wire keys by UTF-8 and retains final source pointers; no locallyDereferenced call |
| Diagnostics | Sorted by file, line, column, pointer, message, then severity; generator-authored summaries with quoted upstream decode/validation details |
| Support needs | Memoized Date use through retained named/inline schemas; each endpoint payload independently selects its coder override; response unions and raw errors select HTTPResponseJSONDecoder as well |
| Filesystem paths / arguments | Used for reading/writing and diagnostic paths only; canonical Stem.openapi in output headers |

Yams compose supplies marks and an independent external-reference scan. YAML
and JSON decoding both use Yams, preserving key order. No Foundation JSONDecoder
allKeys iteration participates in lowering. JSONSerialization is used only to
validate configuration JSON syntax and to read plugin namespaces.
