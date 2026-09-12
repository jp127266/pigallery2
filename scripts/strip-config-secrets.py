#!/usr/bin/env python3
"""git clean filter for config/config.json.

PiGallery2 signs login cookies with Server.sessionSecret, so those keys must
never reach the repo -- but the live file has to keep them, or restarting the
container invalidates every session. A clean filter gives both: the working
file is untouched, while the blob git stores is sanitised.

The key is REMOVED, not emptied. PiGallery2 generates a secret in the config
constructor, before config.json is read (PrivateConfigClass.ts), so an explicit
"sessionSecret": [] overwrites the generated keys with nothing and no code
regenerates them -- cookie-session then throws "Keys must be provided." and
login is impossible. Omitting the key leaves the generated value in place.

Reads config.json on stdin, writes the sanitised version to stdout.
"""
import json
import re
import sys

ENTRY = re.compile(
    r'^[ \t]*"sessionSecret"[ \t]*:[ \t]*\[[^\]]*\],?[ \t]*\r?\n',
    re.MULTILINE,
)
# A comma with nothing but whitespace before the closing brace/bracket is never
# valid JSON, so repairing it is safe. Only fires if sessionSecret was last.
DANGLING_COMMA = re.compile(r',(\s*[}\]])')


def main() -> int:
    config = sys.stdin.read()
    stripped = ENTRY.sub('', config)

    try:
        json.loads(stripped)
    except json.JSONDecodeError:
        stripped = DANGLING_COMMA.sub(r'\1', stripped)
        try:
            json.loads(stripped)
        except json.JSONDecodeError as exc:
            # Fail loudly: emitting malformed JSON here would commit a config
            # that cannot boot. git aborts the operation on a non-zero exit.
            print(f'strip-config-secrets: refusing to emit invalid JSON: {exc}',
                  file=sys.stderr)
            return 1

    sys.stdout.write(stripped)
    return 0


if __name__ == '__main__':
    sys.exit(main())
