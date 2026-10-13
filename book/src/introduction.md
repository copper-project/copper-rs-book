# Introduction

Welcome to **Learning copper-rs**, a hands-on guide to building robots with the
[Copper](https://github.com/copper-project/copper-rs) deterministic robotics operating system.

Most people learn Rust with the amazing [Rust Book](https://rust-book.cs.brown.edu/), so we built it for [copper-rs](https://github.com/copper-project/copper-rs).

This book has been written with the help of AI, for the sake of speed, proper grammar and formatting, but each and every line has been reviewed by a human.

The source for this book is available on
[GitHub](https://github.com/copper-project/copper-rs-book). Feedback and contributions are
welcome.

This book will take you from zero to a running Copper project, one concept at a time. By
the end, you'll understand how to define task graphs, write sensor drivers and processing
pipelines, and run everything with sub-microsecond deterministic scheduling.

## Reading version markers

<div class="version-legend">
<span class="version-marker" data-version="1.0">v1.0</span>
<span class="version-marker" data-version="1.1">v1.1</span>
<span class="version-marker" data-version="1.2">v1.2</span>
<span class="version-marker" data-version="1.3">v1.3</span>
</div>

A marker means “available since this version” for a feature or the API shown. Under a heading,
it applies to that section; beside a paragraph or list item, it applies only there.
Features that predate 1.0 have no marker. Paired patch markers give the minimum
patch on each release line when a feature was backported.

This edition's examples use **1.3.0-dev**. Sections marked **v1.3** currently
require that development checkout; see [Setting Up](./setup.md). Older markers
identify when a capability became available, but the examples use this edition's
APIs and tools. Keep your application and its logreaders on the same version.
Experimental features are identified separately in their chapters.

## Who is this for?

This book is aimed at:

- **Robotics developers** coming from ROS / ROS 2 who want to explore a Rust-native
  alternative
- **Rust developers** interested in robotics and real-time systems
- **Beginners** who want a gentle, progressive introduction to Copper's architecture

No prior Copper experience is required. Familiarity with Rust syntax is helpful but any experience with other programming language should allow you to get through.

Let's get started!
