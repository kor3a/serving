#!/usr/bin/env python
"""Django's command-line utility for administrative tasks."""

import os
import sys

# Django 5.2 requires 3.10, and this codebase uses `X | None` annotations.
# macOS still ships 3.9, so fail with an explanation rather than a traceback.
REQUIRED_PYTHON = (3, 10)


def main():
    if sys.version_info < REQUIRED_PYTHON:
        running = ".".join(str(part) for part in sys.version_info[:3])
        required = ".".join(str(part) for part in REQUIRED_PYTHON)
        sys.exit(
            f"Serving's server needs Python {required}+, but this is {running}.\n"
            f"Install a newer Python (brew install python@3.13) and run "
            f"./setup.sh --recreate."
        )

    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "serving.settings")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Activate the virtualenv and run "
            "`pip install -r requirements.txt`."
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
