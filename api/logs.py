"""Access logging, minus the part that would be a travel diary.

uvicorn's default access line carries the full request target, and for `/plan`
that target is a person's origin, their destination and a timestamp:

    127.0.0.1:52104 - "GET /plan?from=30.0444,31.2357&to=30.1220,31.2450&... " 200

A file of those lines is a record of where people went. The app promises the
opposite in the dialog shown before the OS location prompt -- «ومافيش سجل
للأماكن اللي رحتها», no record of the places you have been -- so the log has to
be made to match the promise before anything is deployed, not after.

What survives redaction is method, path, status and client address, which is
what one maintainer on one box actually uses: error rates per endpoint, and
evidence that a request arrived at all. A per-request coordinate trail is not
something this deployment has any use for.

This is installed as a filter on the `uvicorn.access` *logger* rather than
shipped as a `--log-config` file, for two reasons:

- a flag can be left off. `api.main` is imported however the app is started --
  `uvicorn api.main:app`, gunicorn with uvicorn workers, a container entrypoint
  -- so installing it at import time means there is no launch command that gets
  the unredacted log.
- uvicorn calls `Config.configure_logging()` in `Config.__init__` and imports
  the app later, in `Config.load()`, so by the time this runs uvicorn's own
  `dictConfig` has already been applied and will not undo it. Attaching to the
  logger rather than to the handler also survives a later reconfigure, since
  `dictConfig` replaces a logger's handlers but leaves its filters alone.
"""

from __future__ import annotations

import logging

ACCESS_LOGGER = "uvicorn.access"

# Left in place of the query string. A bare path would be indistinguishable
# from a request that had no query at all, and would read as "nothing to see
# here" to the next person wondering why the log looks thin.
REDACTED = "?<redacted>"

# uvicorn logs the access line as `'%s - "%s %s HTTP/%s" %d'` with args
# (client_addr, method, path_with_query, http_version, status). Only the third
# is rewritten, and the arity is left exactly as it was: `AccessFormatter`
# unpacks all five positionally and raises if it gets a different shape.
_PATH_ARG = 2


class RedactQueryString(logging.Filter):
    """Strip the query string out of a uvicorn access record."""

    def filter(self, record: logging.LogRecord) -> bool:
        args = record.args
        if not isinstance(args, tuple) or len(args) <= _PATH_ARG:
            return True
        target = args[_PATH_ARG]
        if not isinstance(target, str) or "?" not in target:
            return True
        path = target.split("?", 1)[0]
        record.args = (
            args[:_PATH_ARG] + (path + REDACTED,) + args[_PATH_ARG + 1:]
        )
        return True


def install_access_log_redaction() -> None:
    """Attach the filter, once. Called at import of `api.main`."""
    logger = logging.getLogger(ACCESS_LOGGER)
    if any(isinstance(f, RedactQueryString) for f in logger.filters):
        return
    logger.addFilter(RedactQueryString())
