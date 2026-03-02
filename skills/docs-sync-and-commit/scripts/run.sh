#!/usr/bin/env bash
set -euo pipefail

message=""
allow_no_doc=0
no_commit=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      message="$2"
      shift 2
      ;;
    --allow-no-doc)
      allow_no_doc=1
      shift
      ;;
    --no-commit)
      no_commit=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: run.sh [options]

Options:
  -m, --message <msg>  Commit message.
  --allow-no-doc       Allow committing non-doc changes when no docs changed.
  --no-commit          Only run checks, do not commit.
  -h, --help           Show this help.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null

all_files="$(
  {
    git diff --name-only
    git diff --cached --name-only
    git ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u
)"

if [[ -z "$all_files" ]]; then
  echo "No working tree changes."
  exit 0
fi

doc_changed=0
non_doc_changed=0

echo "Changed files:"
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  echo "  - $file"
  if [[ "$file" == "README.md" || "$file" == "AGENTS.md" || "$file" == docs/* || "$file" == *.md ]]; then
    doc_changed=1
  else
    non_doc_changed=1
  fi
done <<< "$all_files"

if [[ $non_doc_changed -eq 1 && $doc_changed -eq 0 && $allow_no_doc -ne 1 ]]; then
  echo "Doc sync check failed: non-doc changes exist but no doc file changed." >&2
  echo "Update README/docs first, or rerun with --allow-no-doc." >&2
  exit 2
fi

if [[ $no_commit -eq 1 ]]; then
  echo "Check passed (no commit mode)."
  exit 0
fi

if [[ -z "$message" ]]; then
  if [[ $doc_changed -eq 1 && $non_doc_changed -eq 1 ]]; then
    message="chore: sync docs and commit project updates"
  elif [[ $doc_changed -eq 1 ]]; then
    message="docs: sync project documentation"
  else
    message="chore: commit project updates"
  fi
fi

git add .
if git diff --cached --quiet; then
  echo "Nothing staged after git add."
  exit 0
fi

git commit -m "$message"
git show --stat --oneline -1
