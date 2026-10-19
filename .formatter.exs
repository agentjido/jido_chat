[
  plugins: [Spark.Formatter],
  locals_without_parens: [
    plugin: 1,
    schema: 1,
    route: 2,
    route: 3,
    client: 2,
    source: 2,
    connection: 1,
    rooms: 1,
    commands: 1
  ],
  inputs: [
    "{mix,.formatter,.credo,.doctor}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  line_length: 120,
  import_deps: []
]
