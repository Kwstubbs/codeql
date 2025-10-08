---
category: minorAnalysis
---
* Fields of certain objects are considered tainted if the object is tainted. This holds, for example, for objects that occur directly as sources in the active threat model (for instance, a remote flow source). This has now been amended to also include array types, such that if an array like `MyPojo[]` is a source, then fields of a tainted `MyPojo` are now also considered tainted.
