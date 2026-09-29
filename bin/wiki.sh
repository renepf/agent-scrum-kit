#!/usr/bin/env bash
# Shared project wiki: seed, query, add, verify, lint. The librarian's only hands.
# Design: protocols/LIBRARIAN.md. No model call happens here; a model only supplies text.
#   WIKI_ROOT    the OKF bundle (default: ./wiki)
#   WIKI_STAGING staging directory (default: <WIKI_ROOT>/../wiki-staging)
#   WIKI_REPOS   source repos, "tag=/abs/path,tag2=/abs/path2"
exec python3 "$(dirname "${BASH_SOURCE[0]}")/wiki.py" "$@"
