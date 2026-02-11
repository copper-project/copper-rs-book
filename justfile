# Default recipe: list available commands
default:
    @just --list

# Build the book
build:
    cd book && mdbook build

# Serve the book locally with live-reload
serve:
    cd book && mdbook serve --open

# Insert a new chapter at the given number and renumber the rest
[doc("insert-chapter <number> <slug> [title]  e.g. just insert-chapter 6 my-new-topic \"My New Topic\"")]
insert-chapter number slug title="":
    #!/usr/bin/env bash
    set -euo pipefail

    SRC_DIR="book/src"
    NEW_NUM="{{ number }}"
    SLUG="{{ slug }}"

    # Derive title: use the explicit argument, or generate from slug
    if [[ -n "{{ title }}" ]]; then
        TITLE="{{ title }}"
    else
        TITLE=$(echo "$SLUG" | sed 's/-/ /g; s/\b\(.\)/\u\1/g')
    fi

    # Validate NEW_NUM is a positive integer
    if ! [[ "$NEW_NUM" =~ ^[0-9]+$ ]] || [[ "$NEW_NUM" -eq 0 ]]; then
        echo "Error: chapter number must be a positive integer, got '$NEW_NUM'" >&2
        exit 1
    fi

    # ── Discover highest chapter number ──────────────────────────────
    HIGHEST=$(ls "$SRC_DIR"/ch[0-9][0-9]-*.md 2>/dev/null \
        | sed 's|.*/ch\([0-9]*\)-.*|\1|' \
        | sort -n \
        | tail -1)

    if [[ -z "$HIGHEST" ]]; then
        echo "Error: no chapter files found in $SRC_DIR" >&2
        exit 1
    fi

    HIGHEST=$((10#$HIGHEST))

    if [[ $NEW_NUM -gt $((HIGHEST + 1)) ]]; then
        echo "Error: chapter $NEW_NUM is too high; highest existing chapter is $HIGHEST." >&2
        echo "       Use $((HIGHEST + 1)) to append at the end." >&2
        exit 1
    fi

    NEW_FILE=$(printf "ch%02d-%s.md" "$NEW_NUM" "$SLUG")

    echo "Inserting new chapter: $SRC_DIR/$NEW_FILE (chapter $NEW_NUM)"
    if [[ $NEW_NUM -le $HIGHEST ]]; then
        echo "Renumbering chapters $NEW_NUM..$HIGHEST → $((NEW_NUM + 1))..$((HIGHEST + 1))"
    fi
    echo ""

    # ── Phase 1: Rename files (highest → lowest to avoid collisions) ─
    for (( i=HIGHEST; i>=NEW_NUM; i-- )); do
        OLD_PREFIX=$(printf "ch%02d" "$i")
        NEW_PREFIX=$(printf "ch%02d" "$((i + 1))")

        OLD_FILE=$(ls "$SRC_DIR"/${OLD_PREFIX}-*.md 2>/dev/null | head -1)
        if [[ -z "$OLD_FILE" ]]; then
            echo "Warning: no file found for $OLD_PREFIX, skipping rename" >&2
            continue
        fi

        OLD_BASENAME=$(basename "$OLD_FILE")
        NEW_BASENAME="${NEW_PREFIX}${OLD_BASENAME#${OLD_PREFIX}}"

        echo "  rename: $OLD_BASENAME → $NEW_BASENAME"
        mv "$SRC_DIR/$OLD_BASENAME" "$SRC_DIR/$NEW_BASENAME"
    done

    # ── Phase 2: Update references in all .md files ──────────────────
    # Process from highest down to avoid double-replacing
    echo ""
    echo "Updating cross-references in .md files..."

    for (( i=HIGHEST; i>=NEW_NUM; i-- )); do
        OLD_PREFIX=$(printf "ch%02d" "$i")
        NEW_PREFIX=$(printf "ch%02d" "$((i + 1))")

        find "$SRC_DIR" -name '*.md' -exec \
            sed -i "s|${OLD_PREFIX}-|${NEW_PREFIX}-|g" {} +

        find "$SRC_DIR" -name '*.md' -exec \
            sed -i "s|Chapter ${i}\\b|Chapter $((i + 1))|g" {} +
    done

    # ── Phase 3: Create the new chapter file ─────────────────────────
    echo ""
    echo "Creating $SRC_DIR/$NEW_FILE"

    cat > "$SRC_DIR/$NEW_FILE" << EOF
    # $TITLE

    <!-- TODO: Write chapter content -->
    EOF

    # ── Phase 4: Insert into SUMMARY.md ──────────────────────────────
    SUMMARY="$SRC_DIR/SUMMARY.md"
    PREV=$((NEW_NUM - 1))

    if [[ "$PREV" -eq 0 ]]; then
        # Inserting as ch01: place before what is now ch02
        ANCHOR_PREFIX=$(printf "ch%02d" "$((NEW_NUM + 1))")
        ANCHOR_LINE=$(grep -n "${ANCHOR_PREFIX}-" "$SUMMARY" | head -1 | cut -d: -f1)
        if [[ -n "$ANCHOR_LINE" ]]; then
            NEW_ENTRY="- [$TITLE](./$NEW_FILE)"
            sed -i "${ANCHOR_LINE}i\\${NEW_ENTRY}" "$SUMMARY"
            echo "Inserted into SUMMARY.md before line $ANCHOR_LINE"
        else
            echo "Warning: could not find anchor in SUMMARY.md to insert new entry" >&2
        fi
    else
        # Insert after the previous chapter
        ANCHOR_PREFIX=$(printf "ch%02d" "$PREV")
        ANCHOR_LINE=$(grep -n "${ANCHOR_PREFIX}-" "$SUMMARY" | head -1 | cut -d: -f1)
        if [[ -n "$ANCHOR_LINE" ]]; then
            NEW_ENTRY="- [$TITLE](./$NEW_FILE)"
            sed -i "${ANCHOR_LINE}a\\${NEW_ENTRY}" "$SUMMARY"
            echo "Inserted into SUMMARY.md after line $ANCHOR_LINE"
        else
            echo "Warning: could not find anchor in SUMMARY.md to insert new entry" >&2
        fi
    fi

    # ── Done ─────────────────────────────────────────────────────────
    echo ""
    echo "Done! New chapter $NEW_NUM created at $SRC_DIR/$NEW_FILE"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $SRC_DIR/$NEW_FILE with your content"
    echo "  2. Review SUMMARY.md to make sure the entry is in the right section"
    echo "  3. Check cross-references with: grep -rn 'ch[0-9]' $SRC_DIR/*.md"
