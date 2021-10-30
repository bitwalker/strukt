# 0.3.0

- ADDED: Support for reusable validation rules via the `Strukt.Validator` behavior
- ADDED: Support for describing validation pipelines for structs using the `validation/1` and `validation/2` macros
- BREAKING CHANGE: When overriding the `validate/1` callback, users must now explicitly call `super/1` to ensure inline
validations are applied (as well as the validation pipeline, but that is newly added). Previously, inline validations
would be run regardless of whether a user overrode `validate/1`
