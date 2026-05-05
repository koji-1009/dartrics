# dartrics

Dart code-quality metrics and unused public-API detection.

`dartrics` re-implements the academically-grounded metric suite (CK, Halstead,
McCabe, Martin, Cognitive Complexity) on top of `package:analyzer`, and
augments `dart analyze`'s `dead_code` lint with a Periphery-style
public-API reachability pass.

## Status

Pre-alpha — landing the metric suite phase by phase ahead of the first
pub.dev release.

## Quickstart

```bash
dart pub global activate dartrics
dartrics analyze lib/ --reporter json
```

## License

MIT.
