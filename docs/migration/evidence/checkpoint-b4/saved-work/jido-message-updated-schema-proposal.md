# Proposed shared schema correction

The frozen MessageUpdated schema requires text to be a string. The original Discord tests contain valid partial updates that have no text. The current schema cannot retain those facts.

Proposed change: allow text to be a string or null in the shared MessageUpdated schema. Keep the field required and keep all other fields unchanged. Update the matching catalog schema. Null means the provider did not supply text. Empty string remains distinct. No provider field is added.

Required checks after approval: native constructor/JSON/catalog tests; Discord null/empty/populated update tests; shared package and affected runtime tests. The schema files have not changed.
