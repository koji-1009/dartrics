# dartrics example

A minimal program that drives a single metric calculator (`CyclomaticComplexity`) over a snippet of source code — useful when embedding dartrics into custom tooling.

For day-to-day use, prefer the CLI:

```bash
dart pub global activate dartrics
dartrics analyze .
dartrics rules --reporter ai
```

`analysis_options.yaml` here shows the minimum threshold + snapshot configuration; copy-paste it into your project to get started.
