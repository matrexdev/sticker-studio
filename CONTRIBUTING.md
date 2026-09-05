# Contributing

Use English for code, comments, documentation, issue reports, and pull requests. Keep comments focused on non-obvious implementation decisions.

## Development

1. Open the Xcode project and resolve its pinned Swift package dependency.
2. Make a focused change without modifying another developer's signing settings.
3. Run the test suite with Command-U.
4. Check affected screens in light and dark appearance, in English and Turkish.
5. For changes to Vision or WhatsApp integration, also test on a physical iPhone.

## Translations

Keep the English source keys identical across localization files. Preserve placeholders such as `%d` and `%@`; pass values through `L10n.text`. Never translate stored pack names, captions, filenames, or identifiers. Add tests when a new formatting pattern is introduced.

## Storage changes

Preserve existing library formats or provide an explicit migration. Keep manifest writes atomic. Never delete image files before a successful manifest commit. Cover deletion scope and failed-write behavior with regression tests.

## Pull requests

Describe the problem, resulting behavior, and validation. Include screenshots for visible changes. Do not commit personal photos, credentials, provisioning profiles, build output, or Xcode user state. Do not add analytics or remote image processing without an explicit project decision.
