# Writing the Copper Book

## Purpose

This book teaches readers to build working Copper applications. Organize the
material around concepts and the problems they solve. Each feature should give
the reader a clear answer to three questions:

1. **Why does this feature exist?** Start with a concrete problem a robot or its
   developer encounters.
2. **When should I use it?** Explain the useful outcome and the requirements or
   tradeoffs that affect that choice.
3. **How do I use it?** Give a short path from a stated starting point to a
   working example with an observable result.

The intended reaction is: “Ah, that is what this is for, and I can use it after
a few copy-pastes.” A reader should experience the feature before needing its
implementation details.

## Build a complete learning path

- Getting-started chapters must work from a fresh environment once their named
  prerequisites are installed. A later chapter may build on a specific earlier
  chapter; identify that starting state and link to it.
- Feature tutorials must state their starting directory, Copper version or
  checkout, required features and tools, and files the reader needs. Reuse an
  existing small example where it makes the path shorter.
- Keep steps minimal, sequential, and sufficient. Include directory changes,
  imports, dependency/feature entries, graph wiring, and startup code needed to
  make the example work. Do not leave essential setup as an exercise.
- Commands and snippets must be copy-pasteable in the stated context. Use one
  consistent project name and set of paths. Include Cargo's `--` separator where
  needed, and use the exact current command and option names.
- Give runnable examples concrete values. If a real deployment requires a
  device address or another user-specific value, identify that edit explicitly
  before the command; keep the first example runnable locally when practical.
- Say whether a snippet replaces a file or belongs in a particular existing
  section. Avoid ellipses or omitted code in examples presented as complete.
- End the exercise with an observable checkpoint: an output value, exported
  record, visible graph, or other result that demonstrates the purpose. Explain
  what the reader should notice. Label variable or illustrative output honestly.
- After the working example, explain how to adapt it to the reader's app and
  address the few likely failures that would prevent the result.

## Write for the reader

- Use plain language and explain unfamiliar terms when first needed.
- Teach behavior and practical choices before API inventories, storage formats,
  or runtime internals. Put deeper reference material after the tutorial or link
  to the relevant reference.
- Do not refer to pull requests, development branches, commit IDs, merge order,
  or implementation history in chapter prose. Link to stable repository paths,
  released documentation, or other chapters for further reading.
- Describe unreleased features by the version readers need, such as
  `1.3.0-dev`, and state experimental status when it affects their use.
- Keep a chapter focused on its concept. Link to prerequisites and related
  tutorials instead of duplicating a long reference or introducing unrelated
  features.

## Verify before opening a PR

- Check documented APIs, feature flags, defaults, commands, and paths against
  the target copper-rs version. The code is authoritative when prose disagrees.
- Run the tutorial's smallest complete example where the environment permits.
  Verify the resulting behavior, not only that Markdown renders. If execution
  requires unavailable hardware or tools, state that limitation in the PR and
  distinguish source verification from an executed example.
- Build the book with `just build` and run `git diff --check`.
- Keep PRs targeted to one learning gap. Write the PR description around what
  readers can now understand and accomplish, plus the validation performed.
- Preserve unrelated working-tree changes. Do not merge, publish, or deploy as
  part of a documentation update unless requested.

Book sources live in `book/src/`; chapter order is defined by
`book/src/SUMMARY.md`. The sibling `../copper-rs` checkout is the usual source
for checking implementation and running repository examples.
